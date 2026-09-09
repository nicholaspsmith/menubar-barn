import AppKit
import BarnCore

extension MenuBarGeometry {
    /// Read the live geometry of the menu bar we manage.
    ///
    /// `auxiliaryTopRightArea` is the strip to the right of the notch; its `minX`
    /// is the first x a status item can occupy. On a display without a notch the
    /// property is nil and the usable area starts at 0.
    static func current(for screen: NSScreen? = NSScreen.main) -> MenuBarGeometry {
        guard let screen else { return MenuBarGeometry(usableMinX: 0, usableMaxX: 0) }
        return MenuBarGeometry(
            usableMinX: screen.auxiliaryTopRightArea?.minX ?? 0,
            usableMaxX: screen.frame.maxX
        )
    }
}
