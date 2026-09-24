// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ApplicationServices
import BarnCore

/// One slot in the agent's layout: where an item really is, and whose it is.
struct HostedSlot {
    let pid: pid_t
    let frame: ItemFrame
    /// The accessibility identifier of the app's button inside the slot, when
    /// the app set one. Barn labels its own two items this way so the line and
    /// the handle can be told apart without guessing from their widths.
    let identifier: String?
}

/// The bar as `MenuBarAgent` lays it out.
struct HostedLayout {
    let slots: [HostedSlot]
    /// The system « button. Present whenever anything is overflowed or ejected.
    let chevron: ItemFrame?
    /// The width of the bar these slots were laid out in — the agent's window,
    /// which is the display's, and what the half-width ceiling is measured
    /// against.
    let barWidth: CGFloat

    func slots(for pid: pid_t) -> [HostedSlot] { slots.filter { $0.pid == pid } }

    func placement(of slot: HostedSlot?) -> Placement {
        HostedBar.placement(of: slot?.frame, chevron: chevron)
    }
}

/// Reads the layout from `MenuBarAgent`, the process that owns every status
/// item on macOS 27.
///
/// Before 27 each app's own accessibility tree said where its item sat, and
/// it was right. On 27 the app's tree still lists the item but its frame is a
/// stale proxy — three items created by one process reported one frame — and
/// an item the agent has ejected keeps reporting a frame it does not have.
/// The agent's window is the only tree whose positions mean anything.
enum AXHostedBar {
    static let agentBundleID = "com.apple.MenuBarAgent"
    private static let messagingTimeout: Float = 1.0

    /// The agent's pid, or nil before macOS 27 (or if it is not running). Its
    /// presence is what switches Barn into hosted mode: the mechanism is tied
    /// to the process, not to a version number.
    static var agentPID: pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == agentBundleID && !$0.isTerminated }?
            .processIdentifier
    }

    static var isHosted: Bool { agentPID != nil }

    /// Nil when the agent is absent or its tree cannot be read (no
    /// Accessibility grant, or it is wedged — it does hang on occasion).
    ///
    /// Reads the agent's windows in turn rather than just the first: they all
    /// publish the same bar, but only one of them hands back the apps'
    /// status-item buttons, and so the identifiers Barn labels its own items
    /// with. The first window that names them is the one used, whole — they
    /// are separate snapshots and disagree mid-reflow, so mixing them
    /// invents slots. See `HostedWindows`. Stops as soon as every slot of
    /// `identifying` has a name, which is normally the second window.
    static func layout(identifying ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> HostedLayout? {
        guard let pid = agentPID, AXMenuBar.isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement],
              let bar = windows.lazy.compactMap({ frame(of: $0) }).first
        else { return nil }

        var readings: [(slots: [HostedSlotReading], chevron: ItemFrame?)] = []
        for window in windows {
            var reading: [HostedSlotReading] = []
            var chevron: ItemFrame?
            for child in (attribute(window, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                guard let frame = frame(of: child) else { continue }
                // The « button is the agent's own, a direct child of the window
                // rather than a slot holding someone's item. Its description is
                // localized, so the role and owner are what identify it.
                if role(of: child) == kAXButtonRole as String, owner(of: child) == pid {
                    chevron = frame
                    continue
                }
                guard let item = (attribute(child, kAXChildrenAttribute) as? [AXUIElement])?.first,
                      let itemPID = owner(of: item)
                else { continue }
                // The agent's own extras — clock, Wi‑Fi, Control Center — are not
                // anyone's status item and are never Barn's to hide.
                guard itemPID != pid else { continue }
                reading.append(HostedSlotReading(
                    pid: itemPID,
                    frame: frame,
                    identifier: attribute(item, kAXIdentifierAttribute) as? String
                ))
            }
            readings.append((reading, chevron))
            if HostedWindows.identified(reading, for: ownPID) { break }
        }
        guard let index = HostedWindows.pickIndex(readings.map(\.slots), naming: ownPID) else {
            return HostedLayout(slots: [], chevron: readings.first?.chevron, barWidth: bar.width)
        }
        let slots = readings[index].slots.map {
            HostedSlot(pid: $0.pid, frame: $0.frame, identifier: $0.identifier)
        }
        let chevron = readings[index].chevron
        return HostedLayout(slots: slots, chevron: chevron, barWidth: bar.width)
    }

    /// The two edges of an app's menu bar the agent lays the trailing items
    /// out against: where its name ends (the title after the Apple menu),
    /// below which items are dropped, and where its last menu ends, past
    /// which items are placed.
    struct MenuEdges: Equatable {
        let appNameRightEdge: CGFloat
        let menusRightEdge: CGFloat
    }

    /// Nil when the app publishes no menu bar, or does not answer.
    static func menuEdges(ofPID pid: pid_t) -> MenuEdges? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar = attribute(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        let titles = (attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        let frames = titles.compactMap { frame(of: $0) }
        guard frames.count >= 2, let last = frames.map(\.maxX).max() else { return nil }
        return MenuEdges(appNameRightEdge: frames[1].maxX, menusRightEdge: last)
    }

    // MARK: - AX plumbing

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }

    private static func owner(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    private static func frame(of element: AXUIElement) -> ItemFrame? {
        guard let position: CGPoint = axValue(element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(element, kAXSizeAttribute, .cgSize),
              size.width > 0
        else { return nil }
        return ItemFrame(minX: position.x, width: size.width)
    }

    private static func axValue<T>(_ element: AXUIElement, _ name: String, _ type: AXValueType) -> T? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(value as! AXValue, type, result) else { return nil }
        return result.pointee
    }
}
