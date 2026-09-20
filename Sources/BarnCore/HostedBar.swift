// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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

    /// Where the drop floor sits relative to the frontmost app's name — the
    /// second title in its menu bar, after the Apple menu. An item whose
    /// virtual left edge lands below `appName.maxX + floorOffset` is dropped
    /// from the bar. Measured with four apps in front (Terminal 120→~154,
    /// Zen 88→~124, Finder 105→~136, iTerm2 109→~142); the agent keeps the
    /// Apple menu and the app's name clear, plus this much.
    public static let floorOffset: CGFloat = 33

    /// The floor assumed when the frontmost app cannot be read. Low on
    /// purpose: a guess below the real floor only makes B wider, while one
    /// above it leaves B in the band and brings the « back.
    public static let ejectionFloor: CGFloat = 143

    public static func floor(appNameRightEdge: CGFloat) -> CGFloat { appNameRightEdge + floorOffset }

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

    // MARK: - Two lines

    /// The band the « is shown for starts this far right of the frontmost
    /// app's last menu title — measured between 22 and 48pt across apps,
    /// presumably the room the agent keeps for the « itself plus a gap that
    /// comes and goes. A's left edge is aimed past the widest seen.
    public static let boundaryMargin: CGFloat = 56

    /// How far below the floor B's left edge is aimed, so a floor measured
    /// a few points off still drops it.
    public static let floorClearance: CGFloat = 16

    /// The widest slot that survives the half-display cliff.
    static func widestSlot(displayWidth: CGFloat) -> CGFloat {
        displayWidth / 2 - floorMargin
    }

    public struct Split: Equatable {
        public let a: CGFloat
        public let b: CGFloat
        /// B hit the half-display cliff before reaching the floor, so its
        /// left edge sits in the band and the « will show. The band is wider
        /// than half the bar — an app whose menus run past ~900pt on a
        /// 1600pt display — and no number of items can cross it without one
        /// of them starting inside it.
        public let bCapped: Bool
    }

    /// Widths for the two lines: A from `lineRightEdge` down to just right
    /// of the boundary, B from there down to just below the floor.
    ///
    /// Everything left of B has a virtual edge below the floor and is dropped
    /// without a «; A sits right of the band, so it is not an overflow
    /// member; B is below the floor, so neither is it. Each is capped under
    /// the cliff — if A is capped, B reaches the rest of the way; if B is
    /// capped there is nothing more two items can do.
    ///
    /// - Parameter boundary: the frontmost app's last menu title's right edge.
    /// - Parameter floor: where the agent starts dropping, from `floor(appNameRightEdge:)`.
    public static func split(
        lineRightEdge: CGFloat,
        boundary: CGFloat,
        floor: CGFloat,
        displayWidth: CGFloat
    ) -> Split {
        let cap = widestSlot(displayWidth: displayWidth)
        let aSlot = min(lineRightEdge - (boundary + boundaryMargin), cap)
        let a = max(aSlot - slotPadding, BarnGeometry.showWidth)
        let aLeft = lineRightEdge - (a + slotPadding)
        let bWanted = aLeft - (floor - floorClearance)
        let bSlot = min(bWanted, cap)
        let b = max(bSlot - slotPadding, BarnGeometry.showWidth)
        return Split(a: a, b: b, bCapped: bWanted > cap)
    }

    /// True when A cannot be placed right of the band at all: the visible
    /// icons reach past the frontmost app's menus, and the agent would start
    /// overflowing them. Barn collapses the leftmost visible icon instead.
    public static func needsCollapse(lineRightEdge: CGFloat, boundary: CGFloat) -> Bool {
        lineRightEdge - (BarnGeometry.showWidth + slotPadding) < boundary + boundaryMargin
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
