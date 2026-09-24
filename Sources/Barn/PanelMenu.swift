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
/// the system. Every menu-bar app is a row, ticked when its icon is out on the
/// bar and unticked when it is in the barn — one switch per app, where the app
/// is, rather than a second checklist somewhere else to keep in step.
///
/// A ticked row has no submenu: clicking it puts that icon in the barn. An
/// unticked one has the app's *actual* menu as its submenu, read live over the
/// accessibility API so it stays usable with its icon off the bar, and "Show on
/// the Bar" sits at the top of it — a submenu's parent never fires an action of
/// its own, so the row's own click cannot be the way back out. One list, so the
/// whole bar is in view at once and there is no second menu to go looking in.
final class PanelMenu: NSObject, NSMenuDelegate {
    private struct Owner {
        let pid: pid_t
        let name: String
        /// Whether the app publishes a menu at all. Known from the sweep, so
        /// an app without one goes straight to its Open row rather than
        /// paying for an accessibility read that will come back empty.
        let hasMenu: Bool
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
    /// - Parameter toggleRow: an item wired by the owner to move that app
    ///   across the line, in whichever direction it currently needs. It is
    ///   never added to a menu: the row's tick fires its action directly, so
    ///   that the tick is a target of its own and the rest of the row keeps
    ///   doing what it did.
    /// - Parameter settingsRow: the footer, wired by the owner to open the
    ///   settings menu in this one's place. Dressed as a caption, but a live row:
    ///   text that names the other menu might as well take you there.
    func build(apps: [PanelApp], hasMenu: (pid_t) -> Bool, toggleRow: (PanelApp) -> NSMenuItem, settingsRow: NSMenuItem) -> NSMenu {
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
            let item = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
            if app.isHidden {
                // In the barn: the row carries the app's own live menu, which
                // is the whole point of the panel. Its click is spoken for,
                // which is why the tick has to be a target of its own.
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                submenu.delegate = self
                ownerForMenu[ObjectIdentifier(submenu)] = Owner(pid: app.pid, name: app.name, hasMenu: hasMenu(app.pid))
                if hasMenu(app.pid) {
                    item.submenu = submenu
                    item.toolTip = "\(app.name) is in the barn. Its own menu is in here; the tick puts its icon back."
                } else {
                    // No menu to present, so press the icon itself — for an app
                    // like Bitwarden that press is how it opens. Falling back to
                    // revealing the bar was worse than useless: picking the app
                    // did something unrelated to the app.
                    item.action = #selector(openApp(_:))
                    item.target = self
                    item.representedObject = RowRef(pid: app.pid, index: -1)
                    item.toolTip = "\(app.name) publishes no menu; clicking the name opens it. The tick puts its icon back."
                }
            } else {
                item.toolTip = "\(app.name) is on the bar. Untick it to put it in the barn."
            }
            item.view = PanelRowView(app: app, item: item, toggle: toggleRow(app))
            menu.addItem(item)
        }

        // The settings live behind a right click, which nothing on screen says.
        menu.addItem(.separator())
        menu.addItem(Self.dressedAsHint(settingsRow, "Right-click the icon for settings"))
        return menu
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
        for row in owner.hasMenu ? AXMenuDriver.rows(forPID: pid) : [] {
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
        // An app that publishes no menu — or looked like it had one and
        // produced no rows — is still reachable: pressing its icon is what it
        // does. For an app like Bitwarden that press is how it opens.
        // Never leave a hidden app with no way in.
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

/// One app's row: a tick that takes clicks of its own, then the app's icon
/// and name, then the submenu arrow where there is a submenu.
///
/// A view rather than a plain row because the two halves do different things.
/// A row in the barn carries the app's live menu, so its click is already
/// spoken for — the tick cannot be the row's action as well, and a tick you
/// can only read is not a switch. So the row draws itself: clicks in the
/// leading strip move the icon across the line, clicks anywhere else do
/// whatever that row did before, and the menu's own tracking still opens the
/// submenu on hover.
///
/// Everything AppKit would have drawn has to be drawn here, highlight
/// included, which is why the metrics below are spelled out rather than
/// inherited.
private final class PanelRowView: NSView {
    /// The leading strip that belongs to the tick. Wider than the glyph: a
    /// 12pt target is a miss waiting to happen, and there is nothing else
    /// out here to hit by accident.
    private static let tickZone: CGFloat = 32
    /// Where the icon starts, and where the title starts after it. The menu's
    /// own text inset is 14pt; these keep the same rhythm with the tick ahead
    /// of them.
    private static let iconX: CGFloat = 32
    private static let titleX: CGFloat = 56
    private static let arrowRoom: CGFloat = 22
    private static let height: CGFloat = 22
    private static let box = NSRect(x: 9, y: 5, width: 13, height: 13)

    private let app: PanelApp
    private weak var item: NSMenuItem?
    private let toggle: NSMenuItem
    private var hot = false
    private var tickHot = false

    /// A row for an app out on the bar has no menu of its own to show and
    /// nothing else to do, so its whole width is the switch. A dead click in
    /// a menu is worse than a redundant one.
    private var bodyIsTheSwitch: Bool { !app.isHidden }

    init(app: PanelApp, item: NSMenuItem, toggle: NSMenuItem) {
        self.app = app
        self.item = item
        self.toggle = toggle
        let title = NSAttributedString(string: app.name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        let width = Self.titleX + ceil(title.size().width) + Self.arrowRoom
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel("\(app.name), \(app.isHidden ? "in the barn" : "on the bar")")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = hot || item?.isHighlighted == true
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        drawTick(highlighted: highlighted)
        if let icon = app.icon {
            icon.draw(in: NSRect(x: Self.iconX, y: 3, width: 16, height: 16),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }
        let colour: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        NSAttributedString(string: app.name, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: colour,
        ]).draw(at: NSPoint(x: Self.titleX, y: 3))
        if item?.submenu != nil { drawArrow(colour: colour) }
    }

    /// A box, not a bare checkmark: a checkmark says what the state is, and a
    /// box says you may change it — which is the whole point of giving the
    /// tick its own target.
    private func drawTick(highlighted: Bool) {
        let ticked = !app.isHidden
        let box = NSBezierPath(roundedRect: Self.box, xRadius: 3.5, yRadius: 3.5)
        if ticked {
            (highlighted ? NSColor.selectedMenuItemTextColor : NSColor.controlAccentColor).setFill()
            box.fill()
        } else {
            (highlighted ? NSColor.selectedMenuItemTextColor : NSColor.tertiaryLabelColor).setStroke()
            box.lineWidth = 1
            box.stroke()
        }
        if tickHot, !ticked {
            NSColor.tertiaryLabelColor.withAlphaComponent(0.25).setFill()
            box.fill()
        }
        guard ticked else { return }
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: Self.box.minX + 3, y: Self.box.midY))
        mark.line(to: NSPoint(x: Self.box.minX + 5.4, y: Self.box.minY + 3.4))
        mark.line(to: NSPoint(x: Self.box.maxX - 2.8, y: Self.box.maxY - 3.4))
        mark.lineWidth = 1.8
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        (highlighted ? NSColor.selectedContentBackgroundColor : .white).setStroke()
        mark.stroke()
    }

    private func drawArrow(colour: NSColor) {
        let x = bounds.maxX - 16
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: bounds.midY + 3.5))
        path.line(to: NSPoint(x: x + 3.5, y: bounds.midY))
        path.line(to: NSPoint(x: x, y: bounds.midY - 3.5))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        colour.setStroke()
        path.stroke()
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { hot = true; updateTickHot(event); needsDisplay = true }
    override func mouseMoved(with event: NSEvent) { updateTickHot(event) }

    override func mouseExited(with event: NSEvent) {
        hot = false
        tickHot = false
        needsDisplay = true
    }

    private func updateTickHot(_ event: NSEvent) {
        let over = isOverTick(event)
        guard over != tickHot else { return }
        tickHot = over
        needsDisplay = true
    }

    private func isOverTick(_ event: NSEvent) -> Bool {
        convert(event.locationInWindow, from: nil).x < Self.tickZone
    }

    // MARK: - Clicks

    /// The tick's strip moves the icon; the rest of the row does whatever the
    /// row does — open the app's own menu, open the app, or, for a row that
    /// does none of those, move the icon as well. A row with a submenu is
    /// left alone out there: the submenu is already open under the pointer,
    /// and closing the panel on the way to nothing would be a surprise.
    override func mouseUp(with event: NSEvent) {
        guard let item else { return }
        if isOverTick(event) || (bodyIsTheSwitch && item.submenu == nil) {
            fire(toggle)
        } else if item.action != nil {
            fire(item)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        fire(toggle)
        return true
    }

    private func fire(_ target: NSMenuItem) {
        guard let action = target.action else { return }
        // Action first, then dismiss: the owner notes the request and the
        // menu's own did-close is what carries it out.
        NSApp.sendAction(action, to: target.target, from: target)
        item?.menu?.cancelTracking()
    }
}
