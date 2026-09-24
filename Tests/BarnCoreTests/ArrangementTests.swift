// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BarnCore

/// The three items only work in one order — B, then A, then the handle —
/// and every width Barn computes assumes it. Measured 2026-09-24, after a
/// resolution change re-placed the whole bar: the handle at 410..444, B
/// placed at 490..1030 and A gone altogether. Every width the hide computed
/// from that was meaningless, B drew a 540pt hole in the middle of the bar,
/// and the read-back — which only ever looked at its own widths — nudged
/// them four times and gave up with the system « still showing.
final class ArrangementTests: XCTestCase {
    private func frame(_ minX: CGFloat, _ width: CGFloat) -> ItemFrame {
        ItemFrame(minX: minX, width: width)
    }

    func testBDroppedBehindAIsTheNormalHiddenState() {
        let arrangement = HostedBar.arrangement(
            a: frame(626, 519), b: nil, handle: frame(1145, 34)
        )
        XCTAssertEqual(arrangement, .sound)
    }

    func testBImmediatelyLeftOfAIsSoundToo() {
        // What the settle looks like before the lines widen.
        let arrangement = HostedBar.arrangement(
            a: frame(795, 17), b: frame(778, 17), handle: frame(812, 34)
        )
        XCTAssertEqual(arrangement, .sound)
    }

    func testAWithNoSlotIsBroken() {
        // Every width is computed from A's right edge. Without it the hide
        // is working from a fallback, which is how B ended up mid-bar.
        XCTAssertNotEqual(HostedBar.arrangement(a: nil, b: frame(490, 540), handle: frame(410, 34)), .sound)
    }

    func testHandleWithNoSlotIsBroken() {
        XCTAssertNotEqual(HostedBar.arrangement(a: frame(626, 519), b: nil, handle: nil), .sound)
    }

    func testHandleLeftOfTheLineIsBroken() {
        // The one arrangement that takes the control away: A's own width
        // pushes the handle off the display.
        XCTAssertNotEqual(HostedBar.arrangement(a: frame(626, 519), b: nil, handle: frame(410, 34)), .sound)
    }

    func testBRightOfAIsBroken() {
        // B reaches down past the floor; right of A it reaches into the
        // visible icons instead, and draws a hole where it lands.
        XCTAssertNotEqual(HostedBar.arrangement(a: frame(448, 300), b: frame(1004, 17), handle: frame(1040, 34)), .sound)
    }

    func testTheReasonNamesWhatIsWrong() {
        guard case let .broken(reason) = HostedBar.arrangement(a: frame(626, 519), b: nil, handle: frame(410, 34)) else {
            return XCTFail("expected the handle left of A to be broken")
        }
        XCTAssertTrue(reason.contains("handle"), "reason should say what moved: \(reason)")
    }

    /// A wide line that the agent has *placed* rather than dropped is a hole
    /// in the bar the width of the line. Anything over the narrow width is
    /// one, wherever it sits.
    func testAStrandedWideLineIsRecognised() {
        XCTAssertTrue(HostedBar.isStrandedLine(frame(490, 540)))
        XCTAssertFalse(HostedBar.isStrandedLine(frame(778, BarnGeometry.showWidth + HostedBar.slotPadding)))
        XCTAssertFalse(HostedBar.isStrandedLine(nil))
    }
}
