import AppKit
import CurtainCore
import OSLog
import StatusItemKit

private let arrangeLog = Logger(subsystem: "com.nicholaspsmith.Curtain", category: "arrange")

/// Curtain — hides a contiguous block of menu-bar icons by widening a status
/// item of its own, never by moving anyone else's.
///
/// See docs/superpowers/specs/2026-08-17-menubar-curtain-design.md for why that
/// distinction is the entire point of the app.
///
/// Two items, because they cannot be one: macOS renders a status item only when
/// its slot fits entirely within the usable area right of the notch, so the
/// curtain — hundreds of points wide — is permanently invisible, and the control
/// has to be a separate narrow item beside the user's own icons.
final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private var handle: Handle!
    private var panel: PanelMenu!
    private let line = Line()
    private var isHidden = true
    /// False until the menu bar has had a chance to place our narrow items.
    private var hasSettled = false
    private var rehideTimer: Timer?
    private var revealMode = RevealModeStore.load(from: .standard)
    private var peekToken = UUID().uuidString
    private static let settleDelay: TimeInterval = 1.5
    /// Comfortably longer than the 5s poll that refreshes it, short enough that a
    /// crashed Curtain returns the sibling icons quickly.
    private static let yieldTTL: TimeInterval = 15

    /// Where to park our two items on a bar we have never seen.
    ///
    /// The preferred-position scale is opaque and relative to whatever else is
    /// installed, and larger means further left. The line must rank left of the
    /// icons to keep and right of the icons to hide; the handle ranks just right
    /// of the line so it lands in the visible strip. The user can Cmd-drag either
    /// one, and macOS persists wherever they leave it.
    private static let defaults: [String: Double] = [
        "NSStatusItem Preferred Position CurtainLine": 600,
        "NSStatusItem Preferred Position CurtainHandle": 590,
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Seed positions before the items exist — macOS reads these when an item
        // is created, and never again.
        for (key, value) in Self.defaults where UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(value, forKey: key)
        }

        controller = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in self?.applyState() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) },
            autosaveName: "CurtainHandle",
            onPrimaryClick: { [weak self] in self?.showPanel() }
        )
        panel = PanelMenu()
        handle = Handle(controller: controller)
        controller.start()
        settleThenApply()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Curtain state

    private func applyState() {
        handle.draw(hidden: isHidden)

        // Never widen before the system has placed the line. An item created —
        // or re-placed — while already wide does not fit at its ranked spot, so
        // macOS drops it wherever it will go and shoves every other icon aside;
        // measured, it landed right of everything and hid the lot.
        guard hasSettled else {
            line.show()
            return
        }
        if isHidden {
            line.hide()
        } else {
            // Ask the sibling apps for their slots *before* collapsing, so the
            // block has somewhere to land. Without this a reveal just slides the
            // icons behind the notch — the bar has about 43pt spare and the block
            // needs ten times that.
            //
            // Re-posted on every poll tick rather than once: each client arms a
            // short self-restore timer from the TTL, so a crashed Curtain can
            // never leave their icons hidden. Refreshing it is what holds the
            // reveal open.
            MenuBarYield.post(.init(state: .yield, token: peekToken, ttl: Self.yieldTTL))
            line.show()
        }
    }

    /// Stay narrow, let the menu bar place us, then apply the real state.
    private func settleThenApply() {
        hasSettled = false
        line.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            self?.hasSettled = true
            self?.applyState()
        }
    }

    /// A dock, undock or resolution change re-places every item, so go narrow and
    /// let the bar settle before widening again.
    @objc private func screensChanged() {
        settleThenApply()
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        // No show/hide row: the handle itself is the toggle, and a menu entry
        // duplicating a left click is just noise.
        menu.removeAllItems()

        if AXMenuBar.isTrusted {
            let stranded = Watchdog.stranded(
                in: MenuBarGeometry.current(),
                ownPID: ProcessInfo.processInfo.processIdentifier
            )
            for item in stranded {
                menu.addItem(disabledItem("⚠ \(item.name) is in the notch dead zone"))
            }
        } else {
            menu.addItem(actionItem("⚠ Grant Accessibility…", #selector(grantTrust)))
        }

        // Only once something is above it, or the menu opens on a stray line.
        if !menu.items.isEmpty { menu.addItem(.separator()) }

        if AXMenuBar.isTrusted {
            let manage = NSMenuItem(title: "Manage Icons", action: nil, keyEquivalent: "")
            manage.submenu = buildManageMenu()
            menu.addItem(manage)
        }

        let reveal = NSMenuItem(title: "When Showing", action: nil, keyEquivalent: "")
        reveal.submenu = buildRevealMenu()
        menu.addItem(reveal)

        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Curtain", #selector(quit), key: "q"))
    }

    private func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    /// One row per menu-bar app, ticked when the curtain is hiding it. Selecting
    /// a row moves that icon across the line.
    ///
    /// A checklist rather than a settings window with an Apply button: each
    /// toggle is a single drag that either lands or reports why not, so there is
    /// no pending state to get out of step with the bar.
    private func buildManageMenu() -> NSMenu {
        let menu = NSMenu()
        let geometry = MenuBarGeometry.current()
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var seen = Set<pid_t>()
        let apps = AXMenuBar.items()
            .filter { $0.pid != ownPID }
            .filter { seen.insert($0.pid).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if apps.isEmpty {
            menu.addItem(disabledItem("No menu bar apps found"))
            return menu
        }

        for app in apps {
            let hidden = CurtainGeometry.placement(of: app.frame, in: geometry) == .hidden
            let item = actionItem(app.name, #selector(toggleAppHidden(_:)))
            item.state = hidden ? .on : .off
            item.representedObject = AppRef(pid: app.pid, name: app.name, isHidden: hidden)
            menu.addItem(item)
        }
        return menu
    }

    /// Rebuilt on every open, so the checkmark always reflects the live choice.
    private func buildRevealMenu() -> NSMenu {
        let menu = NSMenu()
        for mode in RevealMode.allCases {
            let item = actionItem(mode.label, #selector(selectRevealMode(_:)))
            item.representedObject = mode.rawValue
            item.state = mode == revealMode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    /// Left click drops the hidden icons down as a menu, each with its own real
    /// menu inside. Nothing moves and nothing disappears — the whole point of
    /// presenting them here rather than shuffling the bar to make them visible.
    private func showPanel() {
        let apps = HiddenApps.current(
            in: MenuBarGeometry.current(),
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
        controller.popUp(panel.build(
            hidden: apps,
            manage: AXMenuBar.isTrusted ? buildManageMenu() : nil
        ))
    }

    // MARK: - Menu selectors

    /// Left-clicking the handle flips the curtain; the chevron flips with it, so
    /// the icon itself says which way round things are.
    @objc private func toggle() {
        isHidden.toggle()
        if !isHidden { peekToken = UUID().uuidString }

        applyState()
        if isHidden {
            // Widen the line first, then hand the width back — both in the same
            // turn of the run loop, so the icons return together rather than the
            // bar visibly filling in twice.
            //
            // This used to wait 0.6s, back when yielding hid items outright and a
            // sibling restored too early had nowhere to land. Yielding by width
            // keeps every item in place, so there is nothing left to wait for.
            MenuBarYield.post(.init(state: .restore, token: peekToken, ttl: 0))
        }

        rehideTimer?.invalidate()
        rehideTimer = nil
        guard !isHidden, revealMode == .timeout else { return }
        rehideTimer = Timer.scheduledTimer(
            withTimeInterval: RevealModeStore.timeoutDuration,
            repeats: false
        ) { [weak self] _ in
            guard let self, !self.isHidden else { return }
            self.isHidden = true
            self.applyState()
        }
    }

    @objc private func selectRevealMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = RevealMode(rawValue: raw)
        else { return }
        revealMode = mode
        RevealModeStore.save(mode, to: .standard)
        // A mode change must not strand a reveal under the old rules.
        if mode == .toggle {
            rehideTimer?.invalidate()
            rehideTimer = nil
        }
    }

    private final class AppRef: NSObject {
        let pid: pid_t
        let name: String
        let isHidden: Bool
        init(pid: pid_t, name: String, isHidden: Bool) {
            self.pid = pid
            self.name = name
            self.isHidden = isHidden
        }
    }

    /// Move an icon to the other side of the line.
    ///
    /// Both directions need the block revealed first. An icon parked off-screen
    /// cannot be grabbed — the cursor clamps to the display — and the place we
    /// would drop one *to* is off-screen too. During a reveal the line sits in the
    /// middle of the strip with items either side of it, so both moves are
    /// ordinary on-screen drags.
    @objc private func toggleAppHidden(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppRef else { return }
        arrangeLog.notice("request: \(app.isHidden ? "show" : "hide", privacy: .public) \(app.name, privacy: .public); curtain hidden=\(self.isHidden, privacy: .public)")
        // Showing needs room; hiding makes it. Check while the curtain is drawn,
        // which is the layout the restored icon will actually have to fit into.
        if app.isHidden, isHidden, let refusal = roomRefusal(forShowing: app) {
            report(refusal)
            return
        }
        let wasHidden = isHidden
        // Our chevron is not needed until the programmatic re-hide, so it gives
        // up its width like the yielding siblings do. Those 30pt are what decide
        // whether the far end of a wide hidden block clears the notch (measured
        // 2026-09-06: BetterDisplay revealed at x=828, eleven points short).
        controller.setVisible(false)
        if isHidden { toggle() }

        // Wait for the reveal to settle before trusting any position. Siblings
        // yield over a distributed notification that lands a few hundred
        // milliseconds later, and a drag started while the bar is still reflowing
        // grabs one thing and drops another. "Settled" is two consecutive reads
        // that agree; a cap keeps a wedged app from stalling the arrange.
        afterBarSettles { [weak self] in
            guard let self else { return }
            arrangeLog.notice("bar settled; arranging \(app.name, privacy: .public)")
            defer {
                if wasHidden, !self.isHidden {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.toggle() }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.controller.setVisible(true) }
            }

            let ownPID = ProcessInfo.processInfo.processIdentifier
            let geometry = MenuBarGeometry.current()
            let items = AXMenuBar.items()
            let ours = items.filter { $0.pid == ownPID }
            // Restoring: the app's item nearest the line is the one most likely to
            // be drawable. Hiding: the leftmost on-screen one, for the same reason.
            let candidates = items.filter { $0.pid == app.pid }
            guard let lineX0 = ours.map(\.frame.minX).min(),
                  let handleX0 = ours.map(\.frame.maxX).max()
            else {
                arrangeLog.error("own items not readable (\(ours.count, privacy: .public) found); giving up")
                self.reportMissing(app.name, reason: "Curtain could not read its own position on the bar.")
                return
            }
            guard let target0 = app.isHidden
                    ? candidates.max(by: { $0.frame.minX < $1.frame.minX })
                    : candidates.filter({ $0.frame.minX > 0 }).min(by: { $0.frame.minX < $1.frame.minX })
                        ?? candidates.first
            else {
                arrangeLog.error("no status item found for \(app.name, privacy: .public) (pid \(app.pid, privacy: .public)); giving up")
                self.reportMissing(app.name, reason: "\(app.name) did not answer the accessibility API in time, so its icon could not be located.")
                return
            }
            arrangeLog.notice("\(app.isHidden ? "showing" : "hiding", privacy: .public) \(app.name, privacy: .public) from x=\(Int(target0.frame.minX), privacy: .public) w=\(Int(target0.frame.width), privacy: .public) (line \(Int(lineX0), privacy: .public), handle \(Int(handleX0), privacy: .public))")

            let target = target0
            let lineX = lineX0
            let handleX = handleX0
            if app.isHidden, CurtainGeometry.placement(of: target.frame, in: geometry) != .visible {
                let firstDrawable = geometry.usableMinX + geometry.deadZoneMargin
                self.report(
                    .underNotch(name: app.name, at: target.frame.minX, over: firstDrawable - target.frame.minX),
                    for: app.name
                )
                return
            }

            let dropX: CGFloat
            if app.isHidden {
                dropX = self.restoreTarget(for: target, among: items, fallback: handleX + 45, floor: handleX)
            } else {
                self.rememberPlacement(of: target, among: items, rightOf: handleX)
                dropX = lineX - 25
            }

            let result = Arranger.move(target, toX: dropX, in: geometry)
            switch result {
            case .success(let landed):
                arrangeLog.notice("\(app.name, privacy: .public) landed at x=\(Int(landed.minX), privacy: .public) (asked for \(Int(dropX), privacy: .public))")
                // Only once it is actually back does the remembered spot stop
                // mattering; a failed restore should still know where to aim.
                if app.isHidden {
                    PlacementStore.forget(target.key, in: .standard)
                    self.verifyChevronAfterShowing(app)
                }
            case .failure(let failure):
                arrangeLog.error("\(app.name, privacy: .public) failed: \(String(describing: failure), privacy: .public)")
                self.report(failure, for: app.name)
            }
        }
    }

    /// Run `work` once two consecutive reads of the bar (100ms apart) agree, or
    /// after `cap` seconds regardless.
    private func afterBarSettles(cap: TimeInterval = 2.0, _ work: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(cap)
        func snapshot() -> [String] {
            AXMenuBar.items().map { "\($0.pid):\(Int($0.frame.minX)):\(Int($0.frame.width))" }.sorted()
        }
        var previous: [String] = []
        func check() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let current = snapshot()
                if current == previous || Date() >= deadline {
                    work()
                } else {
                    previous = current
                    check()
                }
            }
        }
        // Give the reveal and the yield notifications a head start; agreement
        // between two reads taken before anything has moved proves nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            previous = snapshot()
            check()
        }
    }

    // MARK: - Capacity

    /// Why showing an icon must not go ahead: the bar is full, and the drag would
    /// strand whatever is leftmost — usually our own chevron, the one control
    /// that could put things right.
    private struct NoRoom {
        let name: String
        let victim: String
        let shortfall: CGFloat
    }

    /// Nil when the icon fits. Measured against the current bar with our own
    /// line left out: it lives off-screen by design and would always be
    /// "leftmost". Items already in the notch sliver count as on the bar, so a
    /// bar that is already over capacity refuses too.
    private func roomRefusal(forShowing app: AppRef) -> NoRoom? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let geometry = MenuBarGeometry.current()
        let items = AXMenuBar.items()
        guard let target = items.first(where: { $0.pid == app.pid }) else { return nil }
        let onBar = items.filter { item in
            (item.pid != ownPID || item.frame.width < 100)
                && CurtainGeometry.placement(of: item.frame, in: geometry) != .hidden
        }
        guard let leftmost = onBar.min(by: { $0.frame.minX < $1.frame.minX }) else { return nil }
        let shortfall = CurtainGeometry.shortfallToShow(
            width: target.frame.width,
            leftmostVisibleMinX: leftmost.frame.minX,
            in: geometry
        )
        guard shortfall > 0 else { return nil }
        let victim = leftmost.pid == ownPID ? "Curtain's own chevron" : leftmost.name
        return NoRoom(name: app.name, victim: victim, shortfall: shortfall)
    }

    private func report(_ refusal: NoRoom) {
        let alert = NSAlert()
        alert.messageText = "No room to show \(refusal.name)"
        alert.informativeText = "The menu bar is full. Showing it would push \(refusal.victim) "
            + "into the notch by \(Int(refusal.shortfall.rounded(.up))) pt, where macOS draws nothing. "
            + "Hide another icon first, then try again."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Belt and braces for the pre-check. The bar can reflow in ways the
    /// arithmetic does not predict — on 2026-09-06 a hide drag swapped two
    /// neighbours outright — so after a restore, read our chevron back. If it has
    /// landed in the sliver, say so and offer the one fix that needs no chevron:
    /// hiding the icon again.
    private func verifyChevronAfterShowing(_ app: AppRef) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let geometry = MenuBarGeometry.current()
            guard let chevron = AXMenuBar.items().first(where: { $0.pid == ownPID && $0.frame.width < 100 }),
                  CurtainGeometry.placement(of: chevron.frame, in: geometry) == .deadZone
            else { return }
            let alert = NSAlert()
            alert.messageText = "Curtain's chevron is now hidden by the notch"
            alert.informativeText = "Showing \(app.name) left the bar over capacity: the chevron settled at "
                + "x=\(Int(chevron.frame.minX)), where macOS draws nothing. Hide \(app.name) again to get it back?"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Hide \(app.name) Again")
            alert.addButton(withTitle: "Leave It")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                let undo = NSMenuItem()
                undo.representedObject = AppRef(pid: app.pid, name: app.name, isHidden: false)
                self.toggleAppHidden(undo)
            }
        }
    }

    /// Note where an icon sits before hiding it, so unhiding can put it back in
    /// the same slot instead of dumping it at the end of the row.
    ///
    /// The landmark is the icon immediately to its right, not its own x: an x is
    /// only meaningful against the layout it was measured in, and the bar reflows
    /// every time anything appears, hides or yields.
    ///
    /// Only an icon that sits right of the chevron qualifies as a landmark: a
    /// hidden item, or one that has yielded to a sliver, is inside the block
    /// during a reveal, and aiming beside it drops the restored icon straight
    /// back into hiding.
    private func rememberPlacement(of item: MenuBarItem, among items: [MenuBarItem], rightOf handleX: CGFloat) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let neighbour = items
            .filter { $0.pid != item.pid && $0.pid != ownPID }
            .filter { $0.frame.minX >= item.frame.maxX && $0.frame.minX >= handleX && $0.frame.width > 4 }
            .min { $0.frame.minX < $1.frame.minX }

        PlacementStore.save(
            HidePlacement(rightNeighbour: neighbour?.key, x: item.frame.minX),
            for: item.key,
            to: .standard
        )
    }

    /// Where a restored icon should land: beside the neighbour it used to sit
    /// left of, or failing that wherever it was, or failing that the end of the
    /// row.
    private func restoreTarget(
        for item: MenuBarItem,
        among items: [MenuBarItem],
        fallback: CGFloat,
        floor: CGFloat
    ) -> CGFloat {
        let placement = PlacementStore.placement(for: item.key, in: .standard)
        // An app can own several items (Control Center owns many); take the one
        // that is actually right of the line, or none.
        let neighbour = placement?.rightNeighbour
            .flatMap { id in items.filter { $0.key == id && $0.frame.minX > floor }.min { $0.frame.minX < $1.frame.minX } }
            .map(\.frame)
        return DropTarget.x(for: placement, neighbour: neighbour, fallback: fallback, floor: floor)
    }

    /// An arrange that could not even start. Silence here is what made the
    /// second restore of 2026-09-06 look like the app had done nothing.
    private func reportMissing(_ name: String, reason: String) {
        let alert = NSAlert()
        alert.messageText = "Could not move \(name)"
        alert.informativeText = reason + " Try again in a moment."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Say what went wrong rather than leaving an icon somewhere invisible —
    /// the silence is what made the original bug so hard to see.
    private func report(_ failure: Arranger.Failure, for name: String) {
        let alert = NSAlert()
        alert.messageText = "Could not move \(name)"
        switch failure {
        case .unreachable:
            alert.informativeText = "Its icon is off-screen, so it cannot be dragged. "
                + "Show the icons first, then try again."
        case .didNotLand(_, let at):
            alert.informativeText = "The drag ran but the icon settled at x=\(Int(at)). "
                + "Drag it across the chevron by hand with ⌘ held."
        case .underNotch(_, let at, let over):
            alert.informativeText = "With the icons revealed, \(name)'s icon sits at x=\(Int(at)), "
                + "\(Int(over.rounded(.up))) pt inside the notch, where nothing can grab it. "
                + "Too many icons are hidden for the bar to reveal them all at once: "
                + "show one of the icons nearer the chevron first, or hide fewer."
        }
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func grantTrust() { AXMenuBar.requestTrust() }

    @objc private func toggleLogin() { LoginItem.toggle() }

    @objc private func quit() {
        // Leave the bar as we found it rather than with the block off-screen.
        line.show()
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
