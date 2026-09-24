// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import BarnCore

/// A menu-bar app as the panel lists it: every app gets a row, whether it is
/// in the barn or still out on the bar.
struct PanelApp {
    let name: String
    let pid: pid_t
    /// Bundle identifier, or the name for an app without one — what the saved
    /// order is keyed by.
    let key: String
    let icon: NSImage?
    /// In the barn (pushed off the bar). Anything else — on the bar, in the
    /// notch, in the system « — counts as out.
    let isHidden: Bool
}

/// The barn's contents, presented as a menu.
///
/// Deliberately a real `NSMenu` rather than a custom panel: submenus, keyboard
/// navigation, hover, and dismissal all come for free and look like the rest of
/// the system. Every menu-bar app is a row. An app in the barn has its *actual*
/// menu as its submenu, read live over the accessibility API, so it stays usable
/// without any icon moving anywhere. An app still out on the bar is the same row
/// greyed, with no submenu: clicking it brings the app into the barn, and on the
/// next open it is an ordinary row. One list, so the whole bar is in view at once
/// and there is no second menu to go looking in.
final class PanelMenu: NSObject, NSMenuDelegate {
    private struct Owner {
        let pid: pid_t
        let name: String
    }

    private var ownerForMenu: [ObjectIdentifier: Owner] = [:]

    /// Called when pressing an app's icon through the accessibility API opened
    /// nothing. The app wants a real click, which its off-screen icon cannot
    /// receive — so the owner reveals the bar, clicks it there, and hides again.
    var onOpenByRevealing: ((pid_t) -> Void)?

    /// - Parameter hasMenu: whether an app publishes a menu, answered from a
    ///   snapshot taken off the main thread. Asking AX here — while the panel
    ///   is being built for display — opens and closes the app's own menu,
    ///   which dismisses ours.
    /// - Parameter hideRow: the row for an app that is out on the bar, wired by
    ///   the owner to the same move that the Visible Icons checklist makes. The
    ///   panel only dresses it: grey title, dimmed icon, no submenu.
    /// - Parameter settingsRow: the footer, wired by the owner to open the
    ///   settings menu in this one's place. Dressed as a caption, but a live row:
    ///   text that names the other menu might as well take you there.
    func build(apps: [PanelApp], hasMenu: (pid_t) -> Bool, hideRow: (PanelApp) -> NSMenuItem, settingsRow: NSMenuItem) -> NSMenu {
        let menu = NSMenu()
        // A row whose only job is to hold a submenu has no action, and automatic
        // enabling greys such rows out: the submenu still opened on hover, but
        // clicking the app did nothing at all.
        menu.autoenablesItems = false
        ownerForMenu.removeAll()

        if apps.isEmpty {
            let empty = NSMenuItem(title: "No menu bar apps found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for app in apps {
            guard app.isHidden else {
                menu.addItem(Self.dressedAsOut(hideRow(app), app: app))
                continue
            }
            let item = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
            item.image = Self.rowIcon(app.icon, dimmed: false)
            if hasMenu(app.pid) {
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                submenu.delegate = self
                ownerForMenu[ObjectIdentifier(submenu)] = Owner(pid: app.pid, name: app.name)
                item.submenu = submenu
            } else {
                // No menu to present, so press the icon itself — for an app like
                // Bitwarden that press is how it opens. Falling back to revealing
                // the bar was worse than useless: picking the app did something
                // unrelated to the app.
                item.action = #selector(openApp(_:))
                item.target = self
                item.representedObject = RowRef(pid: app.pid, index: -1)
                item.toolTip = "\(app.name) publishes no menu; this opens it directly."
            }
            menu.addItem(item)
        }

        // The settings live behind a right click, which nothing on screen says.
        menu.addItem(.separator())
        menu.addItem(Self.dressedAsHint(settingsRow, "Right-click the icon for settings"))
        return menu
    }

    /// An app that is out on the bar: the same row, greyed. Not a disabled
    /// item — a disabled item cannot be clicked, and clicking is how it comes in.
    private static func dressedAsOut(_ item: NSMenuItem, app: PanelApp) -> NSMenuItem {
        item.attributedTitle = NSAttributedString(string: app.name, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.disabledControlTextColor,
        ])
        item.image = rowIcon(app.icon, dimmed: true)
        item.submenu = nil
        item.toolTip = "\(app.name) is out on the bar. Click to bring it into the barn."
        return item
    }

    private static func rowIcon(_ icon: NSImage?, dimmed: Bool) -> NSImage? {
        guard let icon else { return nil }
        let size = NSSize(width: 16, height: 16)
        guard dimmed else {
            icon.size = size
            return icon
        }
        return NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.35)
            return true
        }
    }

    /// A line of small grey text. Reads as a caption — no highlight on hover,
    /// which an ordinary enabled row cannot avoid — and is still clickable:
    /// the row's view takes the click itself and fires the row's action.
    private static func dressedAsHint(_ item: NSMenuItem, _ text: String) -> NSMenuItem {
        item.title = text
        item.view = HintView(text: text, item: item)
        return item
    }

    // MARK: - Lazy submenus

    /// Filled when opened, not when built: reading a menu means asking the owning
    /// app to open it, and doing that for every hidden app on every click would
    /// be both slow and rude.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let owner = ownerForMenu[ObjectIdentifier(menu)] else { return }
        let pid = owner.pid
        menu.removeAllItems()
        for row in AXMenuDriver.rows(forPID: pid) {
            if row.isSeparator {
                menu.addItem(.separator())
                continue
            }
            // A row's own title can be several lines (account details, say);
            // keep the first, which is the part that identifies it.
            let title = row.title.components(separatedBy: .newlines).first ?? row.title
            let item = NSMenuItem(
                title: title,
                action: #selector(pressRow(_:)),
                keyEquivalent: row.keyEquivalent
            )
            item.keyEquivalentModifierMask = row.modifiers
            item.target = self
            item.representedObject = RowRef(pid: pid, index: row.index)
            item.isEnabled = row.isEnabled
            menu.addItem(item)
        }
        // An app that looked like it had a menu but produced no rows is still
        // reachable: pressing its icon is what it does. Never leave a hidden app
        // with no way in.
        if menu.items.isEmpty {
            let open = NSMenuItem(title: "Open \(owner.name)", action: #selector(openApp(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = RowRef(pid: pid, index: -1)
            menu.addItem(open)
        }
    }

    // MARK: - Actions

    private final class RowRef: NSObject {
        let pid: pid_t
        let index: Int
        init(pid: pid_t, index: Int) {
            self.pid = pid
            self.index = index
        }
    }

    /// Driving another app's menu has to wait until ours has finished closing.
    /// Pressed inline, the action is swallowed — measured against Tailscale,
    /// where the identical press works standalone and does nothing from here.
    private func afterMenuCloses(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @objc private func pressRow(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef else { return }
        afterMenuCloses { AXMenuDriver.press(rowIndex: ref.index, forPID: ref.pid) }
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? RowRef else { return }
        afterMenuCloses { [weak self] in
            AXMenuDriver.pressItem(forPID: ref.pid)
            // BetterDisplay answers the press with success and opens nothing;
            // it only responds to a real click. Give the press a moment, then
            // check whether anything actually appeared.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                guard !AXMenuDriver.isPresenting(pid: ref.pid) else { return }
                self?.onOpenByRevealing?(ref.pid)
            }
        }
    }
}

/// The footer's view: grey caption text with the menu's own inset, no
/// highlight, and a click — either button — that closes the menu and fires
/// the item's action.
private final class HintView: NSView {
    private weak var item: NSMenuItem?

    init(text: String, item: NSMenuItem) {
        self.item = item
        let label = NSTextField(labelWithString: text)
        label.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        // Sized to the text: a menu grows to its widest row, and a fixed
        // frame here widened the whole panel (267pt against 230 without).
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(label.intrinsicContentSize.width) + 28, height: 22))
        autoresizingMask = [.width]
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            // The menu's own text inset, so the caption lines up with the titles above.
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The label is an NSTextField, which would take the click and drop it;
    /// the row is one target, so every hit inside it is the row's.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func mouseUp(with event: NSEvent) { fire() }
    override func rightMouseUp(with event: NSEvent) { fire() }
    override func accessibilityPerformPress() -> Bool { fire(); return true }

    private func fire() {
        guard let item, let action = item.action else { return }
        // Action first: the owner notes the request, then the menu's own
        // did-close is what carries it out.
        NSApp.sendAction(action, to: item.target, from: item)
        item.menu?.cancelTracking()
    }
}
