// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BarnCore

final class GeometryTests: XCTestCase {
    /// The real built-in display, measured 2026-08-16: notch ends at x=828,
    /// menu bar runs to x=1496.
    private let screen = MenuBarGeometry(usableMinX: 828, usableMaxX: 1496)

    func testItemInTheNotchSliverIsDeadZone() {
        // KeyLight's actual stranded frame: on paper inside the usable area,
        // in practice invisible.
        let stranded = ItemFrame(minX: 837, width: 32)
        XCTAssertEqual(BarnGeometry.placement(of: stranded, in: screen), .deadZone)
    }

    func testItemClearOfTheSliverIsVisible() {
        // Where repositioning in Ice put it, and where it rendered fine.
        XCTAssertEqual(BarnGeometry.placement(of: ItemFrame(minX: 919, width: 32), in: screen), .visible)
    }

    func testItemRestoredIntoTheNotchIsDeadZone() {
        // What quitting Ice did to Tailscale on 2026-08-17.
        XCTAssertEqual(BarnGeometry.placement(of: ItemFrame(minX: 722, width: 24), in: screen), .deadZone)
    }

    func testItemPushedOffTheLeftEdgeIsHidden() {
        XCTAssertEqual(BarnGeometry.placement(of: ItemFrame(minX: -4253, width: 24), in: screen), .hidden)
    }

    func testHideWidthPushesWholeBlockPastUsableEdge() {
        let width = BarnGeometry.hideWidth(lineRightEdge: 871, blockWidth: 280, in: screen)
        // The block hangs off the line's left edge; all of it must end up left
        // of the usable area.
        XCTAssertLessThanOrEqual(871 - width, screen.usableMinX - 280)
        XCTAssertLessThanOrEqual(width, BarnGeometry.maxLineWidth)
    }

    func testHideWidthNeverExceedsTheClamp() {
        let width = BarnGeometry.hideWidth(lineRightEdge: 1490, blockWidth: 9000, in: screen)
        XCTAssertEqual(width, BarnGeometry.maxLineWidth)
    }

    func testDisplayWithoutANotchHasNoDeadZone() {
        // The dead zone is a notch artifact. On an external display the usable
        // area starts at 0 and an item near the left edge draws fine, so the
        // margin must collapse to zero rather than cry wolf.
        let external = MenuBarGeometry(usableMinX: 0, usableMaxX: 2560)
        XCTAssertEqual(BarnGeometry.placement(of: ItemFrame(minX: 4, width: 24), in: external), .visible)
    }
}

/// Capacity: whether an icon can be made visible without stranding whatever is
/// leftmost. Written after 2026-09-06, when unhiding Download Recycler on a full
/// bar pushed Barn's own chevron into the notch — the one control that could
/// have undone it.
final class RoomTests: XCTestCase {
    private let screen = MenuBarGeometry(usableMinX: 828, usableMaxX: 1496)

    func testFullBarReportsTheShortfall() {
        // The chevron sat at x=870, two points clear of the sliver. A 32pt icon
        // restored anywhere to its right shifts it to 838 — 30pt short.
        let short = BarnGeometry.shortfallToShow(width: 32, leftmostVisibleMinX: 870, in: screen)
        XCTAssertEqual(short, 30)
    }

    func testBarWithRoomReportsNoShortfall() {
        XCTAssertEqual(BarnGeometry.shortfallToShow(width: 32, leftmostVisibleMinX: 920, in: screen), 0)
    }

    func testExactFitIsNotAShortfall() {
        // 900 - 32 = 868, which is precisely the first drawable x.
        XCTAssertEqual(BarnGeometry.shortfallToShow(width: 32, leftmostVisibleMinX: 900, in: screen), 0)
    }

    func testAlreadyStrandedLeftmostIsShortBeforeAnythingMoves() {
        XCTAssertEqual(BarnGeometry.shortfallToShow(width: 24, leftmostVisibleMinX: 840, in: screen), 52)
    }

    func testDisplayWithoutANotchOnlyMindsTheEdge() {
        let external = MenuBarGeometry(usableMinX: 0, usableMaxX: 2560)
        XCTAssertEqual(BarnGeometry.shortfallToShow(width: 32, leftmostVisibleMinX: 200, in: external), 0)
        XCTAssertEqual(BarnGeometry.shortfallToShow(width: 32, leftmostVisibleMinX: 10, in: external), 22)
    }
}
