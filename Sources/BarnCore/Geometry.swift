import Foundation

/// The stretch of menu bar a status item may occupy, in screen points.
///
/// `usableMinX` is `NSScreen.auxiliaryTopRightArea.minX` — the right edge of the
/// notch on a notched display, 0 on one without.
public struct MenuBarGeometry: Equatable, Sendable {
    public let usableMinX: CGFloat
    public let usableMaxX: CGFloat

    /// Items whose left edge sits within this many points of `usableMinX` are
    /// unreliable: macOS gives them a slot but draws nothing there.
    ///
    /// Empirical, and the reason this project exists. On the built-in display an
    /// item at x=837 was invisible while one at x=871 drew normally, with the
    /// usable area starting at x=828. Quitting Ice later dropped three more items
    /// at 722/750/792 — inside the notch outright — and all three vanished.
    public let deadZoneMargin: CGFloat

    /// Zero on a display without a notch: the dead zone is a notch artifact, and
    /// an item near the left edge of an external display draws perfectly well.
    var effectiveDeadZoneMargin: CGFloat { usableMinX > 0 ? deadZoneMargin : 0 }

    public init(usableMinX: CGFloat, usableMaxX: CGFloat, deadZoneMargin: CGFloat = 40) {
        self.usableMinX = usableMinX
        self.usableMaxX = usableMaxX
        self.deadZoneMargin = deadZoneMargin
    }
}

/// A status item's slot, as reported by the accessibility API.
public struct ItemFrame: Equatable, Sendable {
    public let minX: CGFloat
    public let width: CGFloat
    public var maxX: CGFloat { minX + width }

    public init(minX: CGFloat, width: CGFloat) {
        self.minX = minX
        self.width = width
    }
}

public enum Placement: Equatable, Sendable {
    /// Drawn where the user can see and click it.
    case visible
    /// Has a slot, draws nothing. The failure this whole app exists to prevent.
    case deadZone
    /// Pushed clear of the usable area — hidden on purpose.
    case hidden
}

public enum BarnGeometry {
    /// `NSStatusItem.length` clamps near 5012pt in practice; stay just under.
    public static let maxLineWidth: CGFloat = 5000

    /// The line still needs a sliver of width to exist as an item at all.
    public static let showWidth: CGFloat = 1

    /// Classify where an item has ended up.
    ///
    /// The two invisible outcomes must not be conflated: an item pushed clear off
    /// the left edge of the display is hidden *on purpose* by the line, while an
    /// item resting inside the notch is stranded *by accident* and the user can
    /// neither see nor click it. Only the second is worth warning about, and
    /// geometry is the only thing that tells them apart — hence the test on the
    /// x=722 case, which is where quitting Ice dropped Tailscale.
    public static func placement(of frame: ItemFrame, in geometry: MenuBarGeometry) -> Placement {
        if frame.maxX <= 0 { return .hidden }
        if frame.minX < geometry.usableMinX + geometry.effectiveDeadZoneMargin { return .deadZone }
        return .visible
    }

    /// How many points short the bar is of showing an icon `width` wide.
    ///
    /// Restoring an icon shifts everything to its left by exactly its width, so
    /// the only question is whether the leftmost visible item — normally
    /// Barn's own chevron — still starts inside the drawable strip afterwards.
    /// Zero means it fits. Anything else is the amount that has to be freed by
    /// hiding something first, and the caller must refuse rather than drag.
    ///
    /// The 2026-09-06 case: the chevron at x=870 on a bar whose first drawable x
    /// is 868. Unhiding a 32pt icon moved it to 838, into the sliver where macOS
    /// gives an item a slot and draws nothing — and since the chevron *is* the
    /// control, nothing could be undone from the bar.
    public static func shortfallToShow(
        width: CGFloat,
        leftmostVisibleMinX: CGFloat,
        in geometry: MenuBarGeometry
    ) -> CGFloat {
        let firstDrawableX = geometry.usableMinX + geometry.effectiveDeadZoneMargin
        return max(0, firstDrawableX - (leftmostVisibleMinX - width))
    }

    /// Width the line must take so a block of `blockWidth`, sitting immediately
    /// to its left, ends up entirely left of the usable area.
    ///
    /// Growing an item pushes everything to its left further left by exactly the
    /// width gained (measured on macOS 26), so the arithmetic is a straight
    /// displacement — no reflow subtleties.
    public static func hideWidth(
        lineRightEdge: CGFloat,
        blockWidth: CGFloat,
        in geometry: MenuBarGeometry
    ) -> CGFloat {
        let needed = (lineRightEdge - geometry.usableMinX) + blockWidth
        return min(max(needed, showWidth), maxLineWidth)
    }
}
