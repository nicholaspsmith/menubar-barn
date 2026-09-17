import Foundation

/// The menu bar as macOS 27 lays it out: one process (`MenuBarAgent`) owns the
/// whole strip and decides, per item, whether it is placed, overflowed into
/// the system « menu, or ejected from the bar altogether.
///
/// Barn's mechanism survives — a wide line still displaces its left-hand
/// neighbours — but the numbers changed, and none of them are documented.
/// Everything here was measured on the 1600pt external display on 2026-09-17;
/// see docs/superpowers/specs/2026-09-17-macos-27-hosted-menu-bar-design.md.
public enum HostedBar {
    /// The agent wraps every slot in this much extra width: a 30pt item reads
    /// as a 46pt slot, a 300pt one as 316.
    public static let slotPadding: CGFloat = 16

    /// An item whose virtual left edge lands below this is ejected. Measured
    /// to the point: a left edge of 143 kept its slot, 142 lost it, with either
    /// Finder or Terminal frontmost. Treated as a starting guess rather than a
    /// law — `narrower(than:)` backs off when the agent disagrees.
    public static let ejectionFloor: CGFloat = 143

    /// How far above the floor the line's own left edge is aimed. Small on
    /// purpose: the first hidden icon's edge is this much minus its width, and
    /// it has to fall *below* the floor to be ejected rather than overflowed.
    public static let floorMargin: CGFloat = 4

    /// Each retry after an ejection narrows the line by this much.
    public static let retryStep: CGFloat = 32

    /// The widest the line can be and still exist.
    ///
    /// Two ceilings. The line's slot must stay under half the display (796pt
    /// survived on a 1600pt bar, 836 did not), and its left edge must stay
    /// above the floor. The second is the one that usually binds, and it is
    /// what makes hiding capacity-free: the line ends just above the floor, so
    /// every icon to its left has a virtual edge below it and is ejected,
    /// however wide the block is.
    public static func hideWidth(
        lineRightEdge: CGFloat,
        displayWidth: CGFloat,
        floor: CGFloat = ejectionFloor
    ) -> CGFloat {
        let byFloor = lineRightEdge - (floor + floorMargin) - slotPadding
        let byHalf = displayWidth / 2 - slotPadding - floorMargin
        return max(min(byFloor, byHalf), BarnGeometry.showWidth)
    }

    public static func narrower(than width: CGFloat) -> CGFloat {
        max(width - retryStep, BarnGeometry.showWidth)
    }

    /// What the agent's tree says about one item.
    ///
    /// No slot means ejected. A slot that overlaps the « button is one of the
    /// overflowed items stacked against it — the agent gives them frames, but
    /// nothing is drawn there. Anything else is on the bar.
    public static func placement(of slot: ItemFrame?, chevron: ItemFrame?) -> Placement {
        guard let slot else { return .hidden }
        guard let chevron else { return .visible }
        let overlaps = slot.minX < chevron.maxX && slot.maxX > chevron.minX
        return overlaps ? .hidden : .visible
    }
}
