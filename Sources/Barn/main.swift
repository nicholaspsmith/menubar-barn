// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import BarnCore
import OSLog
import StatusItemKit

private let arrangeLog = Logger(subsystem: "com.nicholaspsmith.Barn", category: "arrange")
private let sweepLog = Logger(subsystem: "com.nicholaspsmith.Barn", category: "sweep")
private let menuLog = Logger(subsystem: "com.nicholaspsmith.Barn", category: "menu")

/// Barn — hides a contiguous block of menu-bar icons by widening a status
/// item of its own, never by moving anyone else's.
///
/// See docs/superpowers/specs/2026-08-17-menubar-curtain-design.md for why that
/// distinction is the entire point of the app.
///
/// Two items, because they cannot be one: macOS renders a status item only when
/// its slot fits entirely within the usable area right of the notch, so the
/// wall — hundreds of points wide — is permanently invisible, and the control
/// has to be a separate narrow item beside the user's own icons.
final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private var handle: Handle!
    private var panel: PanelMenu!
    private let line = Line()
    /// The second line macOS 27 needs, created only where the agent runs:
    /// on older systems it would just be a 17pt gap in the bar.
    private var lineB: Line?
    private var isHidden = true
    /// The panel is open (between its will-open and did-close).
    private var panelOpen = false
    /// The footer was clicked: pop the settings menu once the panel has gone.
    private var settingsRequested = false
    /// False until the menu bar has had a chance to place our narrow items.
    private var hasSettled = false
    private var rehideTimer: Timer?
    private var revealMode = RevealModeStore.load(from: .standard)
    private var handleStyle = HandleStyleStore.load(from: .standard)
    /// The order the panel lists apps in; empty is alphabetical.
    private var panelOrder = PanelOrderStore.load(from: .standard)
    private var panelOrderWindow: PanelOrderWindowController?
    private var peekToken = UUID().uuidString
    private static let settleDelay: TimeInterval = 1.5
    /// Comfortably longer than the 5s poll that refreshes it, short enough that a
    /// crashed Barn returns the sibling icons quickly.
    private static let yieldTTL: TimeInterval = 15

    /// Where to park our two items on a bar we have never seen.
    ///
    /// The preferred-position scale is opaque and relative to whatever else is
    /// installed, and larger means further left. The line must rank left of the
    /// icons to keep and right of the icons to hide; the handle ranks just right
    /// of the line so it lands in the visible strip. The user can Cmd-drag either
    /// one, and macOS persists wherever they leave it.
    /// Barn used to be called Curtain (bundle id `com.nicholaspsmith.Curtain`).
    /// On the first launch under the new name, carry every setting across —
    /// hidden apps, placements, handle style, reveal mode, and the two status
    /// items' positions — so the rename costs the user nothing but a fresh
    /// Accessibility grant, which macOS keys to the bundle id.
    private static func migrateFromCurtain() {
        let flag = "MigratedFromCurtain"
        let std = UserDefaults.standard
        guard !std.bool(forKey: flag),
              let old = std.persistentDomain(forName: "com.nicholaspsmith.Curtain"), !old.isEmpty
        else { std.set(true, forKey: flag); return }
        for (key, value) in old where std.object(forKey: key) == nil {
            let renamed = key.replacingOccurrences(of: "CurtainLine", with: "BarnLine")
                             .replacingOccurrences(of: "CurtainHandle", with: "BarnHandle")
            std.set(value, forKey: renamed)
        }
        std.set(true, forKey: flag)
    }

    private static let defaults: [String: Double] = [
        "NSStatusItem Preferred Position BarnLine": 600,
        "NSStatusItem Preferred Position BarnHandle": 590,
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.migrateFromCurtain()
        // Seed positions before the items exist — macOS reads these when an item
        // is created, and never again.
        for (key, value) in Self.defaults where UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(value, forKey: key)
        }
        if AXHostedBar.isHosted {
            // B goes immediately left of A: the agent honours a preferred
            // position for a brand-new name, measured from the trailing
            // edge, so A's own plus its narrow slot lands B beside it. If
            // the user has since dragged A, `placeSecondLine` fixes it up.
            let keyB = "NSStatusItem Preferred Position \(Line.secondIdentifier)"
            if UserDefaults.standard.object(forKey: keyB) == nil {
                let a = UserDefaults.standard.double(forKey: "NSStatusItem Preferred Position BarnLine")
                UserDefaults.standard.set(a + BarnGeometry.showWidth + HostedBar.slotPadding, forKey: keyB)
            }
            lineB = Line(autosaveName: Line.secondIdentifier, identifier: Line.secondIdentifier)
        }

        // One attached menu, built per click: the hidden-icons panel on a left
        // click, the management menu on a right or control click. Attaching
        // it (rather than popping one by hand) keeps AppKit's native tracking:
        // a quick click leaves it open, a held click selects on release.
        controller = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in self?.applyState() },
            onBuildMenu: { [weak self] menu in
                guard let self else { return }
                if StatusItemController.isSecondaryClick { self.buildMenu(menu) } else { self.buildPanel(into: menu) }
            },
            autosaveName: "BarnHandle"
        )
        controller.onMenuWillOpen = { [weak self] in
            guard let self else { return }
            self.panelOpen = true
            self.handle.draw(hidden: false, style: self.handleStyle)
        }
        controller.onMenuDidClose = { [weak self] in
            guard let self else { return }
            self.panelOpen = false
            self.handle.draw(hidden: self.isHidden, style: self.handleStyle)
            self.refreshSnapshots()
            if self.settingsRequested {
                self.settingsRequested = false
                self.popSettings()
            }
        }
        panel = PanelMenu()
        panel.onOpenByRevealing = { [weak self] pid in self?.openByRevealing(pid: pid) }
        handle = Handle(controller: controller)
        controller.button?.setAccessibilityIdentifier(Self.handleIdentifier)
        controller.start()
        settleThenApply()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // The band the agent shows its « for starts at the frontmost app's
        // menus, so the split between the two lines follows the frontmost app.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostAppChanged() {
        guard AXHostedBar.isHosted, isHidden, hasSettled else { return }
        // Give the new app a moment to install its menu bar before measuring it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isHidden, self.hasSettled else { return }
            self.hideLine()
        }
    }

    // MARK: - Barn state

    /// What the menus show. Swept off the main thread on every poll and after
    /// the menu closes, never while a menu is opening: the sweep blocks for up
    /// to the AX messaging timeout, and AppKit abandons a status menu whose
    /// `menuNeedsUpdate` blocks that long — the panel used to flash open and
    /// shut whenever another app was frontmost.
    private var hiddenSnapshot: [HiddenApp] = []
    private var strandedSnapshot: [MenuBarItem] = []
    /// Stacked on the agent's « rather than dropped: hidden, but not ours.
    private var overflowedSnapshot: [MenuBarItem] = []
    private var itemsSnapshot: [MenuBarItem] = []
    private var menuPIDs: Set<pid_t> = []
    private var menuProbe: [pid_t: Bool] = [:]
    private var sweepInFlight = false
    /// A sweep asked for while one is running is run afterwards, not dropped:
    /// the later request is the one that knows the bar has moved.
    private var sweepPending = false

    private func refreshSnapshots() {
        guard AXMenuBar.isTrusted else { return }
        guard !sweepInFlight else { sweepPending = true; return }
        sweepInFlight = true
        let geometry = MenuBarGeometry.current()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let known = menuProbe
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = AXMenuBar.items()
            let hidden = HiddenApps.current(in: geometry, ownPID: ownPID)
            let stranded = Watchdog.stranded(in: geometry, ownPID: ownPID)
            // Probe each app for a menu once per launch, not on every poll.
            var probe = known
            for app in hidden where probe[app.pid] == nil { probe[app.pid] = AXMenuDriver.hasMenu(forPID: app.pid) }
            let withMenus = Set(probe.filter { $0.value }.map(\.key))
            DispatchQueue.main.async {
                guard let self else { return }
                self.itemsSnapshot = items
                self.hiddenSnapshot = hidden
                self.strandedSnapshot = stranded
                self.overflowedSnapshot = items.filter { $0.pid != ownPID && $0.hostPlacement == .hidden && $0.frame.minX > 0 }
                    .filter { $0.bundleID != Self.controlCenterBundleID && $0.bundleID != AXHostedBar.agentBundleID }
                self.menuProbe = probe
                self.menuPIDs = withMenus
                self.sweepInFlight = false
                sweepLog.debug("swept: \(hidden.count, privacy: .public) hidden, \(stranded.count, privacy: .public) stranded, \(items.count, privacy: .public) items")
                if self.sweepPending {
                    self.sweepPending = false
                    self.refreshSnapshots()
                }
            }
        }
    }

    /// The sweep `applyState` starts on a hide reads the bar as the line
    /// widens, before macOS has pushed the icons off — so it finds nothing
    /// hidden, and the panel said "No hidden icons" until the next poll. Read
    /// again once the bar has stopped moving.
    private func refreshSnapshotsOnceSettled() {
        afterBarSettles { [weak self] in self?.refreshSnapshots() }
    }

    private func applyState() {
        handle.draw(hidden: isHidden, style: handleStyle)
        refreshSnapshots()

        // Never widen before the system has placed the line. An item created —
        // or re-placed — while already wide does not fit at its ranked spot, so
        // macOS drops it wherever it will go and shoves every other icon aside;
        // measured, it landed right of everything and hid the lot.
        guard hasSettled else {
            showLine()
            return
        }
        if isHidden {
            hideLine()
        } else {
            // Ask the sibling apps for their slots *before* collapsing, so the
            // block has somewhere to land. Without this a reveal just slides the
            // icons behind the notch — the bar has about 43pt spare and the block
            // needs ten times that.
            //
            // Re-posted on every poll tick rather than once: each client arms a
            // short self-restore timer from the TTL, so a crashed Barn can
            // never leave their icons hidden. Refreshing it is what holds the
            // reveal open.
            MenuBarYield.post(.init(state: .yield, token: peekToken, ttl: Self.yieldTTL))
            showLine()
        }
    }

    // MARK: - The lines on macOS 27

    static let handleIdentifier = "BarnHandle"

    /// The hosted hide in place or in progress: the split applied, what it
    /// was computed from, and how many times the agent has disagreed.
    private struct HostedHide {
        var split: HostedBar.Split
        var rightEdge: CGFloat
        var boundary: CGFloat
        var floor: CGFloat
        /// Added to the boundary margin when a « still showed — the band's
        /// start was further right than assumed on this bar.
        var boundaryBump: CGFloat
        var retries: Int
        var verified: Bool
    }
    private var hostedHide: HostedHide?
    private static let hostedRetries = 4
    private static let hostedVerifyDelay: TimeInterval = 0.7
    /// Collapses tried against one boundary. A drag that keeps failing
    /// must not be retried on every poll.
    private var collapseAttempts = 0
    private var collapseBoundary: CGFloat = 0
    private static let collapseAttemptLimit = 3
    /// Re-settles spent putting our own three items back in order, reset the
    /// moment they are.
    private var arrangementRepairs = 0
    private static let arrangementRepairLimit = 3

    private func showLine() {
        line.show()
        lineB?.show()
        hostedHide = nil
    }

    /// Widen the lines. Before 27 that is one constant on one line. On 27
    /// there are two: A from its own right edge down to just past the
    /// frontmost app's menus, B from there down to below the agent's floor,
    /// so that everything left of B is dropped from the bar without the
    /// agent showing its «. Runs on every poll and app switch; when the
    /// numbers have not changed it does nothing.
    private func hideLine() {
        guard AXHostedBar.isHosted, let lineB else { line.hide(width: BarnGeometry.unhostedLineWidth(in: MenuBarGeometry.current())); return }
        if let attempt = hostedHide, !attempt.verified { return }

        let layout = AXHostedBar.layout()
        let display = layout?.barWidth ?? NSScreen.screens.first?.frame.width ?? 1600
        let rightEdge = ownLineSlot(in: layout)?.frame.maxX ?? hostedHide?.rightEdge ?? display
        let front = Self.frontmostMenus()
        let boundary = front?.menusRightEdge ?? display / 2
        let floor = front.map { HostedBar.floor(appNameRightEdge: $0.appNameRightEdge) } ?? HostedBar.ejectionFloor

        if let current = hostedHide, current.verified {
            // Same bar, same app: leave it alone — unless a « has appeared
            // since (something dragged between the lines, a menu that grew),
            // in which case the verify loop gets another go, up to its limit.
            let same = abs(current.rightEdge - rightEdge) < 8 && abs(current.boundary - boundary) < 8
                && abs(current.floor - floor) < 8
            if same, layout?.chevron == nil || current.retries >= Self.hostedRetries { return }
        }
        // Nudges earned against one situation — this app, this edge — do
        // not carry to another.
        let sameSituation = hostedHide.map {
            $0.boundary == boundary && $0.floor == floor && abs($0.rightEdge - rightEdge) < 8
        } ?? false
        let bump = sameSituation ? (hostedHide?.boundaryBump ?? 0) : 0
        let retries = sameSituation ? (hostedHide?.retries ?? 0) : 0

        if HostedBar.needsCollapse(lineRightEdge: rightEdge, boundary: boundary + bump) {
            collapse(rightEdge: rightEdge, boundary: boundary)
            return
        }
        let split = HostedBar.split(lineRightEdge: rightEdge, boundary: boundary + bump, floor: floor - bump / 2, displayWidth: display)
        hostedHide = HostedHide(split: split, rightEdge: rightEdge, boundary: boundary, floor: floor,
                                boundaryBump: bump, retries: retries, verified: false)
        arrangeLog.notice("hosted hide: A ends at x=\(Int(rightEdge), privacy: .public), menus end at \(Int(boundary), privacy: .public), floor \(Int(floor), privacy: .public); A=\(Int(split.a), privacy: .public) B=\(Int(split.b), privacy: .public)")
        line.hide(width: split.a)
        lineB.hide(width: split.b)
        verifyHostedHide()
    }

    /// The frontmost app's menu bar: where its name ends and where its last
    /// menu ends. Nil without Accessibility or when the app answers nothing.
    static func frontmostMenus() -> AXHostedBar.MenuEdges? {
        guard AXMenuBar.isTrusted, let front = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXHostedBar.menuEdges(ofPID: front.processIdentifier)
    }

    /// One of our items in the agent's layout, by the identifier it carries.
    private func ownSlot(_ identifier: String, in layout: HostedLayout?) -> HostedSlot? {
        layout?.slots(for: ProcessInfo.processInfo.processIdentifier).first { $0.identifier == identifier }
    }

    private func ownLineSlot(in layout: HostedLayout?) -> HostedSlot? { ownSlot(Line.identifier, in: layout) }

    /// Read the layout back. Right means: A has a slot, B has none, and
    /// there is no «. A « — or a B with a slot — means the band starts
    /// further right, or the floor sits higher, than assumed; nudge and retry.
    private func verifyHostedHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hostedVerifyDelay) { [weak self] in
            guard let self, var attempt = self.hostedHide, self.isHidden, !attempt.verified else { return }
            guard let layout = AXHostedBar.layout() else {
                attempt.verified = true
                self.hostedHide = attempt
                return
            }
            /// Every path that stops retrying ends here: record the attempt,
            /// re-read the bar, and check we have not walled off our own
            /// control on the way.
            func settle(_ attempt: HostedHide) {
                var attempt = attempt
                attempt.verified = true
                self.hostedHide = attempt
                self.refreshSnapshots()
                // Our own items first: a « raised by our lines being out of
                // order is not somebody else's icon to hide.
                if self.repairArrangement(in: layout) { return }
                self.supersedeChevron(in: layout, attempt: attempt)
            }
            let aPlaced = self.ownLineSlot(in: layout) != nil
            let bPlaced = self.ownSlot(Line.secondIdentifier, in: layout) != nil
            if aPlaced, !bPlaced, layout.chevron == nil {
                arrangeLog.notice("hosted hide: clean after \(attempt.retries, privacy: .public) retries")
                settle(attempt)
                return
            }
            if attempt.split.bCapped {
                // Nothing to retry: the band is wider than half the bar for
                // this app, and B starts inside it whatever we do.
                attempt.retries = Self.hostedRetries
                arrangeLog.notice("hosted hide: menus end at \(Int(attempt.boundary), privacy: .public); the band is wider than half the bar, so the « stays for this app")
                settle(attempt)
                return
            }
            guard attempt.retries < Self.hostedRetries else {
                arrangeLog.error("hosted hide: still showing a « (A placed=\(aPlaced, privacy: .public), B placed=\(bPlaced, privacy: .public)); giving up")
                settle(attempt)
                return
            }
            // A « with B dropped means A is in the band: move the split
            // right. B still placed means the floor is higher than assumed:
            // B needs to reach further down, which the bump also buys it.
            attempt.boundaryBump += bPlaced ? 8 : 16
            attempt.retries += 1
            attempt.split = HostedBar.split(lineRightEdge: attempt.rightEdge,
                                            boundary: attempt.boundary + attempt.boundaryBump,
                                            floor: attempt.floor - attempt.boundaryBump / 2,
                                            displayWidth: layout.barWidth)
            self.hostedHide = attempt
            arrangeLog.notice("hosted hide: « still showing; retrying with A=\(Int(attempt.split.a), privacy: .public) B=\(Int(attempt.split.b), privacy: .public)")
            self.line.hide(width: attempt.split.a)
            self.lineB?.hide(width: attempt.split.b)
            self.verifyHostedHide()
        }
    }

    // MARK: - Collapse

    /// The bar is full for the frontmost app: A cannot sit right of the
    /// app's menus. Do what the agent would, but into the barn: hide the
    /// leftmost visible icon that is not ours, and check again once that
    /// has settled. Persistent, like any hide; ticking it in the panel undoes it.
    private func collapse(rightEdge: CGFloat, boundary: CGFloat) {
        if collapseBoundary != boundary { collapseBoundary = boundary; collapseAttempts = 0 }
        guard collapseAttempts < Self.collapseAttemptLimit else { return }
        // The arrange borrows the menu bar, and with it the keyboard, for a
        // second or two. Not while the user is in the middle of typing; the
        // next poll asks again.
        let sinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        guard sinceKey > 2 else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let geometry = MenuBarGeometry.current()
        // Whatever is leftmost among the icons the agent still has a slot
        // for — placed, or already stacked on its « — is what the agent
        // would take first, and what we take instead. Not filtered against
        // A's edge: while the bar is over capacity the agent shuffles A about,
        // and the snapshot's frames may predate the shuffle.
        let items = itemsSnapshot.isEmpty ? AXMenuBar.items() : itemsSnapshot
        let candidates = items
            .filter { $0.pid != ownPID && $0.bundleID != Self.controlCenterBundleID && $0.bundleID != AXHostedBar.agentBundleID }
            .filter { $0.frame.minX > 0 && $0.placement(in: geometry) != .deadZone }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let victim = candidates.first else {
            arrangeLog.error("collapse: bar is full for menus ending at \(Int(boundary), privacy: .public) but nothing left to hide")
            return
        }
        collapseAttempts += 1
        arrangeLog.notice("collapse: menus end at \(Int(boundary), privacy: .public), A ends at \(Int(rightEdge), privacy: .public); hiding \(victim.name, privacy: .public)")
        let ref = AppRef(pid: victim.pid, name: victim.name, isHidden: false)
        let item = NSMenuItem()
        item.representedObject = ref
        // Off this turn: the arrange reveals, which flips the state this
        // call was reached from.
        DispatchQueue.main.async { [weak self] in self?.toggleAppHidden(item) }
    }

    // MARK: - The handle beside A

    /// Barn's « should be the leftmost visible thing, where the agent's own
    /// would be. If icons sit between A and the handle on launch, drag the
    /// handle up against A once.
    private func placeHandleBesideLine() {
        guard AXHostedBar.isHosted, let layout = AXHostedBar.layout(),
              let a = ownLineSlot(in: layout), let handle = ownSlot(Self.handleIdentifier, in: layout)
        else { return }
        let between = layout.slots.filter { $0.frame.minX >= a.frame.maxX - 1 && $0.frame.maxX <= handle.frame.minX + 1 && $0.pid != ProcessInfo.processInfo.processIdentifier }
        // Left of A the handle would be hidden along with the block — the one
        // arrangement that takes the control away.
        let leftOfLine = handle.frame.maxX <= a.frame.minX + 1
        guard !between.isEmpty || leftOfLine else { return }
        arrangeLog.notice("handle: \(between.count, privacy: .public) icon(s) between A and the handle (left of A: \(leftOfLine, privacy: .public)); moving the handle beside A")
        Arranger.dragOwn(fromX: handle.frame.minX + handle.frame.width / 2, toX: a.frame.maxX + 4)
    }

    /// Re-settles when our own three items are no longer in the only order
    /// that works: B, then A, then the handle.
    ///
    /// Every width the hide computes is measured from A's right edge and
    /// assumes that order. The agent re-places the entire bar on a
    /// resolution change, and when it hands the items back in a different
    /// order the arithmetic is not merely off, it is meaningless. Measured
    /// 2026-09-24, after the display dropped from 2x to 1x: A dropped
    /// altogether, B placed 540pt wide in the middle of the visible strip —
    /// a hole in the bar — and the handle at 410, left of both and off the
    /// display. The read-back saw only its own widths, nudged them four
    /// times and gave up with the system « showing, every five seconds.
    ///
    /// So check the order, and when it is wrong do what a launch does: go
    /// narrow, let the agent place everything again, and drag B and the
    /// handle back beside A. `placeHandleBesideLine` cannot do it alone —
    /// it drags the handle from where it sits, and an item with no slot has
    /// nowhere to drag from.
    ///
    /// Bounded: a re-settle flashes the hidden block back for a moment, and
    /// a bar that will not take the arrangement must not flash it on every
    /// poll.
    /// - Returns: true when it acted, so the caller leaves the bar alone.
    @discardableResult
    private func repairArrangement(in layout: HostedLayout) -> Bool {
        guard isHidden else { return false }
        let a = ownLineSlot(in: layout)?.frame
        let b = ownSlot(Line.secondIdentifier, in: layout)?.frame
        let handleSlot = ownSlot(Self.handleIdentifier, in: layout)?.frame
        // A read with none of our items in it says nothing about where they
        // are — the agent mid-reflow, or the login window's own bar.
        guard a != nil || b != nil || handleSlot != nil else { return false }
        guard case let .broken(reason) = HostedBar.arrangement(a: a, b: b, handle: handleSlot) else {
            arrangementRepairs = 0
            return false
        }
        guard arrangementRepairs < Self.arrangementRepairLimit else {
            // Out of tries. Never leave a wide line the agent has *placed*:
            // it draws its whole width as empty bar, which is the one
            // failure that looks like Barn broke the menu bar. Give the
            // icons back instead and say why — hiding nothing is a better
            // resting state than a hole.
            if HostedBar.isStrandedLine(a) || HostedBar.isStrandedLine(b) {
                arrangeLog.error("arrangement: \(reason, privacy: .public), and a line is stranded on the bar; showing the icons rather than leaving a gap")
                isHidden = false
                handle.draw(hidden: false, style: handleStyle)
                showLine()
                return true
            }
            return false
        }
        arrangementRepairs += 1
        arrangeLog.error("arrangement: \(reason, privacy: .public) — re-settling (attempt \(self.arrangementRepairs, privacy: .public))")
        settleThenApply()
        return true
    }

    /// Stand in for the agent's «, rather than leaving it up.
    ///
    /// Barn's whole claim on macOS 27 is that its own « replaces the
    /// system's. When the read-back has run out of widths to try and a «
    /// is still showing with our three items where they belong, the item in
    /// the band is somebody's icon, and no width of ours will move it — the
    /// loop used to log "giving up" and leave the system « on the bar,
    /// every five seconds, forever.
    ///
    /// So do what the agent is doing, but into the barn: hide the leftmost
    /// visible icon, exactly as unticking it in the panel would, and
    /// let the next poll check again. `collapse` bounds itself to three
    /// tries against one boundary, so a bar that cannot be helped is left
    /// alone rather than emptied one icon at a time.
    private func supersedeChevron(in layout: HostedLayout, attempt: HostedHide) {
        guard isHidden, layout.chevron != nil, attempt.retries >= Self.hostedRetries else { return }
        arrangeLog.notice("chevron: the « is still up with the lines in place; taking the leftmost icon into the barn instead")
        collapse(rightEdge: attempt.rightEdge, boundary: attempt.boundary)
    }

    /// Stay narrow, let the menu bar place us, then apply the real state.
    private func settleThenApply() {
        hasSettled = false
        showLine()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self else { return }
            self.placeHandleBesideLine()
            self.placeSecondLine()
            self.hasSettled = true
            self.applyState()
        }
    }

    /// B belongs immediately left of A. A brand-new item lands where its
    /// seeded position says, which is right for a fresh install; after the
    /// user has dragged A, or on the first launch of this version, it may
    /// not be, so read where it landed and drag it into place if need be.
    private func placeSecondLine() {
        guard AXHostedBar.isHosted, let layout = AXHostedBar.layout(),
              let a = ownLineSlot(in: layout), let b = ownSlot(Line.secondIdentifier, in: layout)
        else { return }
        guard abs(b.frame.maxX - a.frame.minX) > 2 else { return }
        arrangeLog.notice("second line: at \(Int(b.frame.minX), privacy: .public), A at \(Int(a.frame.minX), privacy: .public); moving B beside A")
        Arranger.dragOwn(fromX: b.frame.minX + b.frame.width / 2, toX: a.frame.minX - 4)
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
            // Each warning is also the fix: clicking it tucks the icon into the
            // barn, or re-settles the barn when the icon is already in the block
            // and merely not pushed far enough. A warning the user can only read
            // leaves them to work out which of Barn's own moves undoes it.
            let onNotch = MenuBarGeometry.current().usableMinX > 0
            for item in strandedSnapshot {
                let where_ = onNotch ? "is in the notch dead zone" : "is cut off at the left edge of the bar"
                let fix = actionItem("⚠ \(item.name) \(where_) — click to fix", #selector(tuckIn(_:)))
                fix.representedObject = AppRef(pid: item.pid, name: item.name, isHidden: false)
                menu.addItem(fix)
            }
            // On 27 an icon can end up in the agent's own « — dragged between
            // Barn's two lines, usually. It is off the bar, but not by Barn's
            // doing, and the « it brings with it is the thing Barn exists to
            // replace; say so rather than quietly fighting the drag.
            for item in overflowedSnapshot {
                let fix = actionItem("⚠ \(item.name) is in the system « menu — click to move it into the barn", #selector(tuckIn(_:)))
                fix.representedObject = AppRef(pid: item.pid, name: item.name, isHidden: false)
                menu.addItem(fix)
            }
        } else {
            menu.addItem(actionItem("⚠ Grant Accessibility…", #selector(grantTrust)))
        }

        // Only once something is above it, or the menu opens on a stray line.
        if !menu.items.isEmpty { menu.addItem(.separator()) }

        if AXMenuBar.isTrusted {
            // No visibility checklist here: every row of the panel carries its
            // own tick, and a second list of the same switches is somewhere
            // for the two to disagree.
            menu.addItem(actionItem("Panel Order…", #selector(showPanelOrder)))
        }

        let reveal = NSMenuItem(title: "When Showing", action: nil, keyEquivalent: "")
        reveal.submenu = buildRevealMenu()
        menu.addItem(reveal)

        let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        icon.submenu = buildIconMenu()
        menu.addItem(icon)

        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(actionItem("Quit Barn", #selector(quit), key: "q"))
    }

    private func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    /// The apps the panel lists: one per process, from the last sweep.
    ///
    /// One row per process, and Control Center is one process owning several
    /// items — Wi‑Fi, Bluetooth, the clock, itself. A single tick cannot say
    /// which, and the drag grabbed the clock, which macOS pins (measured
    /// 2026-09-10: didNotLand every time). System Settings ▸ Control Center
    /// already toggles each of those.
    private func menuBarApps() -> [MenuBarItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var seen = Set<pid_t>()
        return itemsSnapshot
            .filter { $0.pid != ownPID }
            .filter { $0.bundleID != Self.controlCenterBundleID && $0.bundleID != AXHostedBar.agentBundleID }
            .filter { seen.insert($0.pid).inserted }
    }

    /// Every app as the panel lists it, in the chosen order.
    private func panelApps() -> [PanelApp] {
        let geometry = MenuBarGeometry.current()
        let apps = menuBarApps().map { item in
            PanelApp(
                name: item.name,
                pid: item.pid,
                key: item.key,
                icon: NSRunningApplication(processIdentifier: item.pid)?.icon,
                isHidden: item.placement(in: geometry) == .hidden
            )
        }
        return PanelOrderStore.ordered(apps, key: \.key, name: \.name, by: panelOrder)
    }

    @objc private func showPanelOrder() {
        if panelOrderWindow == nil {
            panelOrderWindow = PanelOrderWindowController { [weak self] order in
                self?.panelOrder = order
                PanelOrderStore.save(order, to: .standard)
            }
        }
        panelOrderWindow?.show(apps: panelApps())
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

    /// Barn or chevron, ticked for the current choice.
    private func buildIconMenu() -> NSMenu {
        let menu = NSMenu()
        for style in HandleStyle.allCases {
            let item = actionItem(style.label, #selector(selectHandleStyle(_:)))
            item.representedObject = style.rawValue
            item.state = style == handleStyle ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectHandleStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = HandleStyle(rawValue: raw)
        else { return }
        handleStyle = style
        HandleStyleStore.save(style, to: .standard)
        handle.draw(hidden: isHidden, style: style)
    }

    /// Left click drops the barn's contents down as a menu: every app, ticked
    /// when it is out on the bar and unticked when it is in the barn. The tick
    /// is a target of its own — it has to be, because the rest of the row is
    /// already the app's live menu — and clicking it moves that icon across
    /// the line. Nothing moves and nothing disappears on merely opening the
    /// panel: the whole point of presenting them here rather than shuffling
    /// the bar.
    private func buildPanel(into menu: NSMenu) {
        let built = panel.build(
            apps: panelApps(),
            hasMenu: { [menuPIDs] in menuPIDs.contains($0) },
            toggleRow: { [unowned self] app in
                // Out on the bar, `tuckIn` — it knows the icon that is already
                // left of the line and needs a re-settle rather than a drag.
                // In the barn, the plain move back across.
                let row = self.actionItem(app.name, app.isHidden ? #selector(self.toggleAppHidden(_:)) : #selector(self.tuckIn(_:)))
                row.representedObject = AppRef(pid: app.pid, name: app.name, isHidden: app.isHidden)
                return row
            },
            settingsRow: actionItem("", #selector(openSettings))
        )
        menu.autoenablesItems = false
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }
    }

    /// The panel's footer: swap the panel for the settings menu.
    ///
    /// The footer's view fires this while the panel is still tracking, and a
    /// menu popped while another is closing is dropped without a word
    /// (measured 2026-09-23: a fixed 0.15s wait opened nothing). So the pop
    /// waits for the panel's own did-close. Not through the attached menu:
    /// that one asks the current event which menu to build, and the event is
    /// the click on the footer — a left click, so the panel again.
    @objc private func openSettings() {
        menuLog.notice("settings requested from the panel (panel open: \(self.panelOpen, privacy: .public))")
        if panelOpen {
            settingsRequested = true
        } else {
            popSettings()
        }
    }

    private func popSettings() {
        // Off this turn of the run loop: the did-close callback runs inside
        // the old menu's teardown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            self.buildMenu(menu)
            menuLog.notice("popping the settings menu (\(menu.items.count, privacy: .public) rows)")
            self.handle.draw(hidden: false, style: self.handleStyle)
            // Returns when the menu has closed, like a tracked press would.
            self.controller.popUp(menu)
            menuLog.notice("settings menu closed")
            self.handle.draw(hidden: self.isHidden, style: self.handleStyle)
            self.refreshSnapshots()
        }
    }

    // MARK: - Menu selectors

    /// Left-clicking the handle flips the barn; the icon flips with it, so
    /// the icon itself says which way round things are.
    @objc private func toggle() {
        isHidden.toggle()
        if isHidden {
            rehide()
        } else {
            peekToken = UUID().uuidString
            applyState()
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
            self.rehide()
        }
    }

    /// End a reveal: hand the yielded width back and widen the line(s).
    ///
    /// Before 27 the two go in the same turn of the run loop, so the icons
    /// return together rather than the bar visibly filling in twice. On 27
    /// the order flips and there is a pause between: the lines are sized
    /// from where A's slot ends, and while the siblings are still narrow
    /// that edge sits too far right by their width — the first split then
    /// puts A in the band and the « flashes until the retries catch up.
    private func rehide() {
        MenuBarYield.post(.init(state: .restore, token: peekToken, ttl: 0))
        if AXHostedBar.isHosted {
            handle.draw(hidden: true, style: handleStyle)
            afterBarSettles(cap: 1.0) { [weak self] in
                guard let self, self.isHidden else { return }
                self.applyState()
                self.refreshSnapshotsOnceSettled()
            }
        } else {
            applyState()
            refreshSnapshotsOnceSettled()
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

    static let controlCenterBundleID = "com.apple.controlcenter"

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

    /// Put an icon in the barn, whichever way it is out.
    ///
    /// An icon right of the line is out on the bar (or lost in the notch, or
    /// stacked on the system «) and is dragged across like the checklist does.
    /// An icon already left of the line but still showing — cut off at the
    /// screen edge because the block grew after the line was sized — needs no
    /// drag at all: go narrow, let the bar settle, and size the line again.
    @objc private func tuckIn(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppRef else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let items = itemsSnapshot.isEmpty ? AXMenuBar.items() : itemsSnapshot
        let lineX = items.filter { $0.pid == ownPID }.map(\.frame.minX).min() ?? 0
        let leftOfLine = items.filter { $0.pid == app.pid }.allSatisfy { $0.frame.maxX <= lineX + 1 }
        if leftOfLine, isHidden {
            arrangeLog.notice("tuck in: \(app.name, privacy: .public) is already left of the line; re-settling")
            settleThenApply()
        } else {
            toggleAppHidden(sender)
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
        // Showing needs room; hiding makes it. Check while the icons are hidden,
        // which is the layout the restored icon will actually have to fit into.
        if app.isHidden, isHidden, !AXHostedBar.isHosted, let refusal = roomRefusal(forShowing: app) {
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
        withRoomToArrange { [weak self] in
            guard let self else { return }
            arrangeLog.notice("bar settled; arranging \(app.name, privacy: .public)")
            defer {
                self.giveBackMenuBar()
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
                self.reportMissing(app.name, reason: "Barn could not read its own position on the bar.")
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
            if app.isHidden, target.placement(in: geometry) != .visible {
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

    // MARK: - Opening an app that needs a real click

    /// Reveal the bar, click the app's icon where it now sits, and hide again
    /// once whatever it opened has closed. The only way in for an app that
    /// ignores the accessibility press (BetterDisplay): its icon is off-screen
    /// while hidden, so no click can reach it there.
    private func openByRevealing(pid: pid_t) {
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "the app"
        guard isHidden else { return }
        arrangeLog.notice("open by revealing: \(name, privacy: .public)")
        toggle()
        // Not a timed reveal: it ends when the user is done with the menu.
        rehideTimer?.invalidate()
        rehideTimer = nil
        withRoomToArrange { [weak self] in
            guard let self else { return }
            let geometry = MenuBarGeometry.current()
            guard let item = AXMenuBar.items()
                    .filter({ $0.pid == pid && $0.frame.width < 100 })
                    .max(by: { $0.frame.minX < $1.frame.minX }),
                  item.placement(in: geometry) == .visible
            else {
                arrangeLog.error("open by revealing: \(name, privacy: .public) icon not on screen after reveal")
                self.giveBackMenuBar()
                self.toggle()
                self.reportMissing(name, reason: "Its icon could not be brought on screen to click it — too many icons are hidden for the bar to reveal them all.")
                return
            }
            // The click goes to the app's icon, so the bar can go back first;
            // the icon keeps its place either way.
            self.giveBackMenuBar()
            Arranger.click(atX: item.frame.minX + item.frame.width / 2)
            arrangeLog.notice("open by revealing: clicked \(name, privacy: .public) at x=\(Int(item.frame.minX), privacy: .public)")
            self.rehideWhenDone(pid: pid, seen: false, deadline: Date().addingTimeInterval(120))
        }
    }

    /// Poll until the app has shown something and then closed it, or nothing
    /// appears within a couple of seconds, or the deadline passes; then hide.
    private func rehideWhenDone(pid: pid_t, seen: Bool, deadline: Date, started: Date = Date()) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.isHidden else { return }
            let presenting = AXMenuDriver.isPresenting(pid: pid)
            let nowSeen = seen || presenting
            let gaveUp = !nowSeen && Date().timeIntervalSince(started) > 2.5
            if (nowSeen && !presenting) || gaveUp || Date() >= deadline {
                arrangeLog.notice("open by revealing: done (seen=\(nowSeen, privacy: .public)); hiding again")
                self.toggle()
                return
            }
            self.rehideWhenDone(pid: pid, seen: nowSeen, deadline: deadline, started: started)
        }
    }

    // MARK: - Room to arrange

    /// Run `work` once the revealed bar has settled — and, on 27, once it
    /// fits.
    ///
    /// A drag is only deterministic while everything it touches is placed.
    /// When the frontmost app's menus leave no room for the revealed block,
    /// the agent stacks the leading items on its « at one set of
    /// coordinates, and a drag there grabs and drops whatever it likes:
    /// measured on 2026-09-17, a collapse of KeyLight took Rectangle and
    /// Claude Usage with it. So if the settled reveal shows a «, Barn takes
    /// the menu bar for itself — a regular app for a moment, whose bar is
    /// one word wide — lets the agent lay everything out, and only then
    /// arranges. `giveBackMenuBar` returns focus to the app that had it.
    private func withRoomToArrange(_ work: @escaping () -> Void) {
        afterBarSettles { [weak self] in
            guard let self else { return work() }
            guard AXHostedBar.isHosted, AXHostedBar.layout()?.chevron != nil else { return work() }
            arrangeLog.notice("reveal does not fit the frontmost app's menus; taking the menu bar to arrange")
            self.takeMenuBar()
            self.afterBarSettles(cap: 1.5, work)
        }
    }

    private var lentBy: NSRunningApplication?

    private func takeMenuBar() {
        guard lentBy == nil else { return }
        lentBy = NSWorkspace.shared.frontmostApplication
        if NSApp.mainMenu == nil {
            // The app menu's title is the bundle's name, whatever this says.
            let bar = NSMenu()
            let app = NSMenuItem(title: "Barn", action: nil, keyEquivalent: "")
            app.submenu = NSMenu(title: "Barn")
            bar.addItem(app)
            NSApp.mainMenu = bar
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func giveBackMenuBar() {
        guard let previous = lentBy else { return }
        lentBy = nil
        NSApp.setActivationPolicy(.accessory)
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: previous)
        }
        previous.activate()
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
                && item.placement(in: geometry) != .hidden
        }
        guard let leftmost = onBar.min(by: { $0.frame.minX < $1.frame.minX }) else { return nil }
        let shortfall = BarnGeometry.shortfallToShow(
            width: target.frame.width,
            leftmostVisibleMinX: leftmost.frame.minX,
            in: geometry
        )
        guard shortfall > 0 else { return nil }
        let victim = leftmost.pid == ownPID ? "Barn's own chevron" : leftmost.name
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
                  chevron.placement(in: geometry) == .deadZone
            else { return }
            let alert = NSAlert()
            alert.messageText = "Barn's chevron is now hidden by the notch"
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
        // Leave the bar as we found it rather than with the block off-screen,
        // and the siblings at their width rather than waiting out the TTL.
        showLine()
        MenuBarYield.post(.init(state: .restore, token: peekToken, ttl: 0))
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

// Handle `--login on|off|status` and exit before any UI exists. Start at Login is
// SMAppService.mainApp, which can only register the calling process's own bundle,
// so this is the only way an installer or script can turn it on.
LoginCLI.runIfRequested()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
