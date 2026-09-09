import AppKit
import ApplicationServices

/// One row of another app's status-item menu.
struct AXMenuRow {
    let index: Int
    let title: String
    let isEnabled: Bool
    /// The row's shortcut, ready for `NSMenuItem`. Empty when it has none.
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
    var isSeparator: Bool { title.isEmpty }
}

/// Reads and drives another app's status-item menu through the accessibility
/// API, while that item is parked off-screen.
///
/// This is what makes hiding an icon survivable. An off-screen item can still be
/// *activated* — but its menu then draws off-screen too (measured at x=-4355),
/// so pressing it is useless on its own. Reading the menu instead and presenting
/// the rows ourselves means a hidden app stays fully usable without moving a
/// single icon. Verified end to end: rows read by name, a chosen row pressed,
/// and the target app's handler fired.
///
/// Needs only the Accessibility grant Barn already holds — no Automation
/// permission, because nothing goes through System Events.
enum AXMenuDriver {
    private static let timeout: Float = 1.0

    /// The rows of an app's first status-item menu, in order.
    static func rows(forPID pid: pid_t) -> [AXMenuRow] {
        guard let menu = menu(forPID: pid, allowPress: true) else { return [] }
        defer { close(menu) }
        return children(of: menu).enumerated().map { index, element in
            AXMenuRow(
                index: index,
                title: string(element, kAXTitleAttribute) ?? "",
                isEnabled: bool(element, kAXEnabledAttribute) ?? true,
                keyEquivalent: shortcut(of: element),
                modifiers: modifiers(of: element)
            )
        }
    }

    // MARK: - Shortcuts

    /// AX publishes a row's shortcut, so the panel can show it the way the app's
    /// own menu does — Rectangle's halves and thirds are unreadable without it.
    private static func shortcut(of element: AXUIElement) -> String {
        if let character = string(element, "AXMenuItemCmdChar"), !character.isEmpty {
            return character.lowercased()
        }
        guard let virtual = int(element, "AXMenuItemCmdVirtualKey"),
              let scalar = Self.functionKeys[virtual]
        else { return "" }
        return String(UnicodeScalar(scalar)!)
    }

    /// The modifier bits are their own little dialect: command is *implied*
    /// unless bit 3 says otherwise, which is why Rectangle's ⌃⌥ shortcuts need
    /// that bit read rather than assumed.
    private static func modifiers(of element: AXUIElement) -> NSEvent.ModifierFlags {
        guard let bits = int(element, "AXMenuItemCmdModifiers") else { return [] }
        var flags: NSEvent.ModifierFlags = []
        if bits & 0x01 != 0 { flags.insert(.shift) }
        if bits & 0x02 != 0 { flags.insert(.option) }
        if bits & 0x04 != 0 { flags.insert(.control) }
        if bits & 0x08 == 0 { flags.insert(.command) }
        return flags
    }

    /// Virtual key codes that have no character, mapped to the private-use
    /// scalars `NSMenuItem` draws as arrows and function keys.
    private static let functionKeys: [Int: UInt32] = [
        0x7E: 0xF700, 0x7D: 0xF701, 0x7B: 0xF702, 0x7C: 0xF703,  // arrows
        0x7A: 0xF704, 0x78: 0xF705, 0x63: 0xF706, 0x76: 0xF707,  // F1–F4
        0x60: 0xF708, 0x61: 0xF709, 0x62: 0xF70A, 0x64: 0xF70B,  // F5–F8
        0x65: 0xF70C, 0x6D: 0xF70D, 0x67: 0xF70E, 0x6F: 0xF70F,  // F9–F12
        0x24: 0x000D,  // return
        0x30: 0x0009,  // tab
        0x31: 0x0020,  // space
        0x33: 0x0008,  // delete
        0x35: 0x001B,  // escape
    ]

    /// True when the app exposes a menu we can present. Mullvad and Raycast do
    /// not, and fall back to being revealed in the bar instead.
    ///
    /// Never presses the item. For an app whose icon opens a window rather than a
    /// menu, pressing *is* the action — probing Bitwarden this way threw its
    /// window open just from building the panel. An app that only constructs its
    /// menu on press therefore shows no submenu here, which is the right trade:
    /// merely listing what is hidden must not set anything off.
    static func hasMenu(forPID pid: pid_t) -> Bool {
        guard let menu = menu(forPID: pid, allowPress: false) else { return false }
        defer { close(menu) }
        return !children(of: menu).isEmpty
    }

    /// Activate a row by index. Index rather than title: several rows can share a
    /// title, and separators have none at all.
    @discardableResult
    static func press(rowIndex: Int, forPID pid: pid_t) -> Bool {
        guard let menu = menu(forPID: pid, allowPress: true) else { return false }
        let rows = children(of: menu)
        guard rows.indices.contains(rowIndex) else {
            close(menu)
            return false
        }
        // Do not cancel this menu: pressing the row is what dismisses it, and
        // cancelling first would throw away the action.
        return AXUIElementPerformAction(rows[rowIndex], kAXPressAction as CFString) == .success
    }

    /// Press the status item itself, which for an app with no menu — Bitwarden,
    /// say — is how it opens. The only way in for apps the panel cannot read.
    @discardableResult
    static func pressItem(forPID pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar = element(app, "AXExtrasMenuBar"),
              let item = children(of: bar).first
        else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// True while the app has something on screen: a menu, a popover, a window.
    ///
    /// Read from the window server, not the accessibility tree. BetterDisplay
    /// keeps the element that hosted its menu — children and all — for ten
    /// seconds or more after the menu has visibly closed, so an AX-based check
    /// left the bar revealed long after the user was done. The on-screen window
    /// list empties the instant the menu goes. Tiny placeholder windows (some
    /// apps keep a 1×1) are ignored.
    static func isPresenting(pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return false }
            return width > 20 && height > 20
        }
    }

    // MARK: - AX plumbing

    /// - Parameter allowPress: whether we may press the status item to make its
    ///   menu appear. Only safe once the user has asked for that app's menu —
    ///   pressing an item that opens a window instead of a menu launches it.
    private static func menu(forPID pid: pid_t, allowPress: Bool) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar = element(app, "AXExtrasMenuBar"),
              let item = children(of: bar).first
        else { return nil }

        if let menu = children(of: item).first { return menu }
        guard allowPress else { return nil }
        // Some apps only build the menu once the item is pressed.
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        return children(of: item).first
    }

    private static func close(_ menu: AXUIElement) {
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    private static func element(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of e: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &value) == .success,
              let kids = value as? [AXUIElement]
        else { return [] }
        return kids
    }

    private static func string(_ e: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func int(_ e: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func bool(_ e: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
