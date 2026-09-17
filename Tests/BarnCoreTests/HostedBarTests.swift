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
