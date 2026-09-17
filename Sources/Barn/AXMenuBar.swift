import AppKit
import ApplicationServices
import BarnCore

/// One app's status item, as the accessibility API sees it.
struct MenuBarItem {
    let name: String
    let bundleID: String?
    let pid: pid_t
    var frame: ItemFrame
    /// On macOS 27, the agent's verdict on where this item is; nil before,
    /// when the frame alone says. An ejected item has no frame at all, so it
    /// carries an off-screen sentinel that the geometry reads the same way.
    var hostPlacement: Placement? = nil

    /// Stable across relaunches, unlike a pid — what remembered placements are
    /// filed under. Falls back to the name for apps with no bundle identifier.
    var key: String { bundleID ?? name }

    /// Where the item is. Every classification goes through here so the two
    /// sources of truth — the agent on 27, the frame before it — never get
    /// mixed within one decision.
    func placement(in geometry: MenuBarGeometry) -> Placement {
        hostPlacement ?? BarnGeometry.placement(of: frame, in: geometry)
    }

    /// The frame an ejected item is given: entirely left of x=0, which is what
    /// "hidden" meant before 27, so sorting and reachability checks written
    /// against real frames keep working.
    static func ejectedFrame(width: CGFloat) -> ItemFrame {
        ItemFrame(minX: -width - 1, width: width)
    }
}

/// Reads every app's status item position through the accessibility API.
///
/// AX is the only public way to learn where a status item really is. An app's
/// own `NSWindow` frame is a proxy that disagrees with the truth by hundreds of
/// points, and `CGWindowListCopyWindowInfo` attributes every item to Control
/// Center, which hosts them — so it gives geometry without identity. AX gives
/// both, and it reads items parked off-screen just as happily as visible ones.
///
/// Not everything is legible this way: apps that expose no AX status item —
/// Mullvad and Raycast on this machine — simply do not appear. They can still be
/// hidden by Barn; they just cannot be inspected or arranged for.
enum AXMenuBar {
    /// Apps can wedge; never block the menu waiting on one.
    private static let messagingTimeout: Float = 0.4

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Processes that answered "no status item" recently, so the next sweep can
    /// skip them. Most of the ~70 running processes have no menu-bar item, and a
    /// few of those — updaters, helpers — never answer the accessibility API at
    /// all, so each one costs the full messaging timeout every time it is asked.
    /// Asked once a minute instead, they cost nothing in between. An app that
    /// *gains* a status item is picked up within that minute.
    private static var noBarUntil: [pid_t: Date] = [:]
    private static let noBarTTL: TimeInterval = 60
    private static let lock = NSLock()

    /// Every process is asked concurrently, so a sweep costs about as much as
    /// the slowest single answer rather than the sum of all of them.
    ///
    /// This is what kept the panel from opening: two sweeps per click, two or
    /// three per hide, all on the main thread, and every unresponsive process
    /// adding 0.4s to each. With a couple of stuck helpers running, a hide could
    /// block Barn for five seconds or more, and clicks made in that window
    /// appeared to do nothing until it finished (2026-09-06).
    static func items() -> [MenuBarItem] {
        guard isTrusted else { return [] }
        let perApp = perAppItems()
        guard AXHostedBar.isHosted else { return dropPhantoms(perApp) }
        guard let layout = AXHostedBar.layout() else {
            // The agent could not be read this time. Its slots are the only
            // trustworthy positions, so rather than serve stale per-app frames
            // as if they were real, say nothing until the next sweep.
            return []
        }
        return hostedItems(perApp: perApp, layout: layout)
    }

    /// Merge what each app claims with what the agent laid out.
    ///
    /// The agent is authoritative for everything it placed or overflowed: one
    /// item per slot, with the slot's real frame. An app whose own tree lists
    /// an item but which has no slot has been ejected — off the bar, in the
    /// « menu or not — and is reported hidden with the width its own tree
    /// gives, since that is all that is left of it.
    static func hostedItems(perApp: [MenuBarItem], layout: HostedLayout) -> [MenuBarItem] {
        var result: [MenuBarItem] = []
        var claimed: [pid_t: [MenuBarItem]] = [:]
        // The agent and Control Center publish extras trees of their own —
        // clock, Wi‑Fi, and the rest — that the agent never lays out as
        // slots. Without a slot they would read as ejected and turn up in the
        // panel as hidden apps.
        let system: Set<String?> = [AXHostedBar.agentBundleID, App.controlCenterBundleID]
        for item in perApp where !system.contains(item.bundleID) {
            claimed[item.pid, default: []].append(item)
        }

        for slot in layout.slots {
            guard let app = NSRunningApplication(processIdentifier: slot.pid) else { continue }
            result.append(MenuBarItem(
                name: app.localizedName ?? "Unknown",
                bundleID: app.bundleIdentifier,
                pid: slot.pid,
                frame: slot.frame,
                hostPlacement: layout.placement(of: slot)
            ))
        }
        // An app can own several items (BetterDisplay does), and the agent can
        // have ejected some of them but not others; whatever it did not place
        // is reported once each, hidden.
        for (pid, items) in claimed {
            let placed = layout.slots(for: pid).count
            for item in items.dropFirst(placed) {
                var ejected = item
                ejected.frame = MenuBarItem.ejectedFrame(width: item.frame.width)
                ejected.hostPlacement = .hidden
                result.append(ejected)
            }
        }
        return result
    }

    /// Every app's own account of its status items. Right about which apps
    /// have one and how wide; on 27, wrong about where.
    private static func perAppItems() -> [MenuBarItem] {
        let now = Date()
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy != .prohibited, !app.isTerminated else { return false }
            lock.lock(); defer { lock.unlock() }
            if let until = noBarUntil[app.processIdentifier], until > now { return false }
            return true
        }

        var perApp = [[MenuBarItem]](repeating: [], count: apps.count)
        var barless: [pid_t] = []
        let resultsLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard let bar = statusItemBar(of: element) else {
                resultsLock.lock(); barless.append(app.processIdentifier); resultsLock.unlock()
                return
            }
            var found: [MenuBarItem] = []
            for child in children(of: bar) {
                guard let frame = frame(of: child) else { continue }
                found.append(MenuBarItem(
                    name: app.localizedName ?? "Unknown",
                    bundleID: app.bundleIdentifier,
                    pid: app.processIdentifier,
                    frame: frame
                ))
            }
            resultsLock.lock(); perApp[index] = found; resultsLock.unlock()
        }

        lock.lock()
        for pid in barless { noBarUntil[pid] = now.addingTimeInterval(noBarTTL) }
        // Forget processes that have exited, so the table cannot grow forever.
        let alive = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        noBarUntil = noBarUntil.filter { alive.contains($0.key) }
        lock.unlock()

        return perApp.flatMap { $0 }
    }

    /// Remove items that cannot really be on the bar: a slot that overlaps
    /// another app's slot is not laid out, whatever the API says. BetterDisplay
    /// briefly publishes a 310pt item on top of half the bar whenever its icon
    /// comes on screen; taking that frame at face value made a restore "land"
    /// on it and hid the real icon's failure. Our own line overlaps the hidden
    /// block by design and is left alone.
    static func dropPhantoms(_ items: [MenuBarItem]) -> [MenuBarItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return items.filter { item in
            guard item.pid != ownPID else { return true }
            return !items.contains { other in
                other.pid != item.pid && other.pid != ownPID
                    && other.frame.width < item.frame.width
                    && other.frame.minX >= item.frame.minX + 2
                    && other.frame.maxX <= item.frame.maxX - 2
            }
        }
    }

    // MARK: - AX plumbing

    /// The bar holding status items — `AXExtrasMenuBar`, and only that.
    ///
    /// Falling back to `AXMenuBar` looks tempting for accessory apps but is
    /// wrong: for a regular app that attribute is the *app menu* (Apple, File,
    /// Edit, View, Window…), whose items all sit at the left of the screen and
    /// therefore read as stranded. It flooded the menu with a warning per menu
    /// title per app.
    private static func statusItemBar(of app: AXUIElement) -> AXUIElement? {
        copyElement(app, "AXExtrasMenuBar")
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func frame(of element: AXUIElement) -> ItemFrame? {
        guard let position: CGPoint = axValue(element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(element, kAXSizeAttribute, .cgSize),
              size.width > 0
        else { return nil }
        return ItemFrame(minX: position.x, width: size.width)
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(value as! AXValue, type, result) else { return nil }
        return result.pointee
    }
}
