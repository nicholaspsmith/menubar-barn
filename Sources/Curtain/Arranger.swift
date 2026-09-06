import AppKit
import CurtainCore

/// Moves another app's status icon across the line, by synthesizing the Cmd-drag
/// a user would perform by hand.
///
/// This is the one place Curtain writes something it does not own, and it is
/// deliberately rare: setup only, never continuous. Ice's habit of re-asserting
/// positions constantly is what stranded an icon in the notch in the first place.
///
/// Every drag is read back. A drag that did not land is reported by name rather
/// than assumed — the missing feedback loop being precisely what made Ice's
/// failure silent.
enum Arranger {
    enum Failure: Error {
        /// The icon is off-screen, so no cursor can reach it.
        case unreachable(name: String)
        /// The drag ran but the icon is not where it was asked to go.
        case didNotLand(name: String, at: CGFloat)
        /// Revealed, but sitting under the notch: the hidden block is wider than
        /// the bar can show at once, so this icon has no point a cursor can grab.
        case underNotch(name: String, at: CGFloat, over: CGFloat)
    }

    /// Vertical centre of the menu bar in the top-left space `CGEvent` uses.
    /// AX reports item frames in the same space, so its numbers feed straight in.
    private static let menuBarY: CGFloat = 14

    /// Drag `item` to `targetX`, then confirm.
    static func move(
        _ item: MenuBarItem,
        toX targetX: CGFloat,
        in geometry: MenuBarGeometry
    ) -> Result<ItemFrame, Failure> {
        let first = attempt(item, toX: targetX, in: geometry)
        guard case .failure(.didNotLand) = first else { return first }
        // A drag can miss when the bar is still reflowing under the cursor — a
        // sibling's yield landing late, an app adding an item as its icon comes
        // on screen (BetterDisplay does). One more try after it settles is cheap
        // and, measured, usually enough.
        Thread.sleep(forTimeInterval: 0.4)
        guard let fresh = AXMenuBar.items()
            .filter({ $0.pid == item.pid && abs($0.frame.width - item.frame.width) < 2 })
            .min(by: { abs($0.frame.minX - item.frame.minX) < abs($1.frame.minX - item.frame.minX) })
        else { return first }
        return attempt(fresh, toX: targetX, in: geometry)
    }

    private static func attempt(
        _ item: MenuBarItem,
        toX targetX: CGFloat,
        in geometry: MenuBarGeometry
    ) -> Result<ItemFrame, Failure> {
        guard item.frame.minX > 0 else { return .failure(.unreachable(name: item.name)) }

        drag(fromX: item.frame.minX + item.frame.width / 2, toX: targetX)
        // Give the bar a moment to settle before believing anything.
        Thread.sleep(forTimeInterval: 0.25)

        // An app can own several items (BetterDisplay does); judge the one that
        // ended up nearest the target, not whichever the API lists first.
        guard let landed = AXMenuBar.items()
            .filter({ $0.pid == item.pid })
            .map(\.frame)
            .min(by: { abs($0.minX - targetX) < abs($1.minX - targetX) })
        else {
            return .failure(.didNotLand(name: item.name, at: item.frame.minX))
        }
        // Landing within a slot's width of the target is success; the bar snaps
        // items to positions, so exactness is neither offered nor needed.
        guard abs(landed.minX - targetX) < 60 else {
            return .failure(.didNotLand(name: item.name, at: landed.minX))
        }
        return .success(landed)
    }

    /// A plain left click at `x` on the menu bar — what a user does to open an
    /// icon's menu. For apps that ignore the accessibility press and only
    /// answer a real click (BetterDisplay).
    static func click(atX x: CGFloat) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let origin = NSEvent.mouseLocation
        let point = CGPoint(x: x, y: menuBarY)
        func post(_ type: CGEventType, at p: CGPoint) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
            else { return }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, at: point)
        usleep(50_000)
        post(.leftMouseDown, at: point)
        usleep(60_000)
        post(.leftMouseUp, at: point)
        let height = NSScreen.screens.first?.frame.height ?? 0
        post(.mouseMoved, at: CGPoint(x: origin.x, y: height - origin.y))
    }

    private static func drag(fromX: CGFloat, toX: CGFloat, steps: Int = 14) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Where the pointer was before we borrowed it. Moving someone's cursor to
        // the menu bar is startling enough; leaving it there is rude.
        let origin = NSEvent.mouseLocation
        // Keep the user's real mouse from fighting the synthetic drag.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags = .maskCommand) {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }

        func post(_ type: CGEventType, _ x: CGFloat) {
            post(type, at: CGPoint(x: x, y: menuBarY))
        }

        post(.mouseMoved, fromX)
        usleep(70_000)
        post(.leftMouseDown, fromX)
        usleep(70_000)
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, fromX + (toX - fromX) * progress)
            usleep(14_000)
        }
        usleep(70_000)
        post(.leftMouseUp, toX)

        // Put the pointer back. `NSEvent.mouseLocation` is bottom-left origin and
        // CGEvent is top-left, so the y flips around the primary screen's height.
        let height = NSScreen.screens.first?.frame.height ?? 0
        post(.mouseMoved, at: CGPoint(x: origin.x, y: height - origin.y), flags: [])
    }
}
