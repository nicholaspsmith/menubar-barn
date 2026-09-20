// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BarnCore

/// macOS 27 lays the bar out in one process and ejects any item whose virtual
/// left edge falls below a floor, or whose slot reaches half the display. All
/// numbers here were measured on the 1600pt external display, 2026-09-17.
final class HostedHideWidthTests: XCTestCase {
    func testLineStopsJustAboveTheFloor() {
        // Line's slot ends at 980; the widest it can be and still exist is
        // 980 − 143 − margin, minus the 16pt the agent adds around a slot.
        let width = HostedBar.hideWidth(lineRightEdge: 980, displayWidth: 3000)
        let leftEdge = 980 - (width + HostedBar.slotPadding)
        XCTAssertEqual(leftEdge, HostedBar.ejectionFloor + HostedBar.floorMargin)
    }

    func testHalfTheDisplayCapsTheLine() {
        // 796 survived, 836 did not: the slot must stay under 800 on a 1600pt bar.
        let width = HostedBar.hideWidth(lineRightEdge: 1400, displayWidth: 1600)
        XCTAssertLessThan(width + HostedBar.slotPadding, 800)
        XCTAssertGreaterThan(width + HostedBar.slotPadding, 760)
    }

    func testLineNearTheLeftEdgeCannotWidenAtAll() {
        // Nothing to push: a line already at the floor stays a sliver.
        XCTAssertEqual(HostedBar.hideWidth(lineRightEdge: 150, displayWidth: 1600), BarnGeometry.showWidth)
    }

    func testEachRetryShrinksByAStep() {
        XCTAssertEqual(HostedBar.narrower(than: 700), 700 - HostedBar.retryStep)
        XCTAssertEqual(HostedBar.narrower(than: 10), BarnGeometry.showWidth)
    }
}

/// The agent's tree is the only place a slot's real position lives. Classify
/// what it says about one app's item.
final class HostedPlacementTests: XCTestCase {
    private let chevron = ItemFrame(minX: 763, width: 17.5)

    func testASlotClearOfTheChevronIsVisible() {
        XCTAssertEqual(HostedBar.placement(of: ItemFrame(minX: 788, width: 34), chevron: chevron), .visible)
    }

    func testASlotStackedOnTheChevronIsHidden() {
        // Mullvad while overflowed: 736..780 against the button at 763..780.5.
        XCTAssertEqual(HostedBar.placement(of: ItemFrame(minX: 736, width: 44), chevron: chevron), .hidden)
    }

    func testNoSlotIsHidden() {
        XCTAssertEqual(HostedBar.placement(of: nil, chevron: chevron), .hidden)
    }

    func testWithoutAChevronEverySlotIsVisible() {
        XCTAssertEqual(HostedBar.placement(of: ItemFrame(minX: 736, width: 44), chevron: nil), .visible)
    }
}

/// Two lines: A placed just right of the frontmost app's menus, B dropped
/// below the floor. Numbers from the 2026-09-17 pair probe on the 1600pt
/// display: A 205pt at 600..821 beside Terminal's menus ending at 562, B
/// 440pt with its left edge at 130, no « anywhere.
final class HostedSplitTests: XCTestCase {
    func testLinesMeetAtTheBoundaryAndReachBelowTheFloor() {
        // iTerm2 frontmost: name ends at 109, menus at 562.
        let floor = HostedBar.floor(appNameRightEdge: 109)
        let split = HostedBar.split(lineRightEdge: 821, boundary: 562, floor: floor, displayWidth: 1600)
        let aLeft = 821 - (split.a + HostedBar.slotPadding)
        let bLeft = aLeft - (split.b + HostedBar.slotPadding)
        XCTAssertEqual(aLeft, 562 + HostedBar.boundaryMargin)
        XCTAssertEqual(bLeft, floor - HostedBar.floorClearance)
        XCTAssertEqual(floor, 142)
        XCTAssertLessThan(split.a + HostedBar.slotPadding, 800)
        XCTAssertLessThan(split.b + HostedBar.slotPadding, 800)
    }

    func testBarnsRealLineOnThisDisplay() {
        // Right edge 961, Terminal frontmost. The single line could not do
        // this: its left edge would have to be below 143 with a slot under
        // 800, and 961 − 143 is more than that.
        let split = HostedBar.split(lineRightEdge: 961, boundary: 562, floor: 142, displayWidth: 1600)
        let aLeft = 961 - (split.a + HostedBar.slotPadding)
        let bLeft = aLeft - (split.b + HostedBar.slotPadding)
        XCTAssertGreaterThanOrEqual(aLeft, 562 + HostedBar.boundaryMargin)
        XCTAssertLessThan(bLeft, 142)
    }

    func testAIsCappedWhenTheBoundaryIsFarLeft() {
        // Finder's menus end at 392; A would want 961 − 16 − 432 = 513, fine.
        // With a boundary at 100 A would want 829 and hits the cap instead;
        // B then has to reach the rest of the way.
        let split = HostedBar.split(lineRightEdge: 961, boundary: 100, floor: 142, displayWidth: 1600)
        XCTAssertLessThan(split.a + HostedBar.slotPadding, 800)
        let aLeft = 961 - (split.a + HostedBar.slotPadding)
        let bLeft = aLeft - (split.b + HostedBar.slotPadding)
        XCTAssertLessThan(bLeft, 142)
    }

    func testNoRoomLeavesBothNarrow() {
        // The boundary is past the line: nothing can be hidden by width
        // here; the collapse has to make room first.
        let split = HostedBar.split(lineRightEdge: 500, boundary: 560, floor: 142, displayWidth: 1600)
        XCTAssertEqual(split.a, BarnGeometry.showWidth)
    }

    // The floor follows the app's name: a short name lets the agent keep
    // more of the bar, so B has to reach further down under Zen than under
    // Terminal.
    func testFloorFollowsTheAppName() {
        XCTAssertEqual(HostedBar.floor(appNameRightEdge: 88), 121)
        XCTAssertEqual(HostedBar.floor(appNameRightEdge: 120), 153)
        let zen = HostedBar.split(lineRightEdge: 961, boundary: 606, floor: HostedBar.floor(appNameRightEdge: 88), displayWidth: 1600)
        let terminal = HostedBar.split(lineRightEdge: 961, boundary: 378, floor: HostedBar.floor(appNameRightEdge: 120), displayWidth: 1600)
        let zenBLeft = 961 - (zen.a + 16) - (zen.b + 16)
        let terminalBLeft = 961 - (terminal.a + 16) - (terminal.b + 16)
        XCTAssertLessThan(zenBLeft, 121)
        XCTAssertLessThan(terminalBLeft, 153)
        XCTAssertLessThan(zenBLeft, terminalBLeft)
    }

    func testABandWiderThanHalfTheBarCannotBeCrossed() {
        // Menus to 1081 on a 1600pt bar (a synthetic app): B would need 948pt.
        let split = HostedBar.split(lineRightEdge: 1244, boundary: 1081, floor: 173, displayWidth: 1600)
        XCTAssertTrue(split.bCapped)
        XCTAssertFalse(HostedBar.split(lineRightEdge: 961, boundary: 606, floor: 121, displayWidth: 1600).bCapped)
    }

    func testCollapseIsNeededWhenAHasNoRoom() {
        XCTAssertTrue(HostedBar.needsCollapse(lineRightEdge: 600, boundary: 562))
        XCTAssertFalse(HostedBar.needsCollapse(lineRightEdge: 700, boundary: 562))
    }
}
