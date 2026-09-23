// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BarnCore

/// `MenuBarAgent` publishes the same bar as several accessibility windows, and
/// only one of them hands back each app's status-item *button* — the others
/// answer with the owning application element, which carries no identifier.
///
/// Measured 2026-09-22 on macOS 27, four windows, every one of them listing
/// the same twelve children: window 1 answered with the buttons (7 of its 11
/// slots, the other four being the agent's own groups) and was the only one to
/// carry `BarnLine`; windows 0, 2 and 3 answered with the application element
/// and carried nothing. Reading `windows.first` — window 0 — is how Barn lost
/// sight of its own line, and with it the handle.
final class HostedWindowMergeTests: XCTestCase {
    private func slot(_ pid: pid_t, _ x: CGFloat, _ width: CGFloat, _ identifier: String? = nil) -> HostedSlotReading {
        HostedSlotReading(pid: pid, frame: ItemFrame(minX: x, width: width), identifier: identifier)
    }

    func testIdentifierComesFromWhicheverWindowCarriesIt() {
        let merged = HostedWindows.merge([
            [slot(10, 375, 796), slot(20, 1179, 34)],
            [slot(10, 375, 796, "BarnLine"), slot(20, 1179, 34)],
        ])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.identifier, "BarnLine")
    }

    func testOneSlotPerPositionHoweverManyWindowsRepeatIt() {
        let window = [slot(10, 375, 796, "BarnLine"), slot(20, 1179, 34)]
        XCTAssertEqual(HostedWindows.merge([window, window, window, window]).count, 2)
    }

    func testOneAppsThreeItemsStayApart() {
        // Barn's own items all share its pid; only the frame tells them apart.
        let merged = HostedWindows.merge([
            [slot(10, 698, 34), slot(10, 1145, 17), slot(10, 1162, 17)],
            [slot(10, 698, 34, "BarnHandle"), slot(10, 1145, 17, "BarnLineB"), slot(10, 1162, 17, "BarnLine")],
        ])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.map(\.identifier), ["BarnHandle", "BarnLineB", "BarnLine"])
    }

    func testFirstSeenOrderAndFrameAreKept() {
        let merged = HostedWindows.merge([
            [slot(20, 1179, 34), slot(10, 375, 796)],
            [slot(10, 375, 796, "BarnLine"), slot(20, 1179, 34, "Other")],
        ])
        XCTAssertEqual(merged.map(\.frame.minX), [1179, 375])
        XCTAssertEqual(merged.map(\.identifier), ["Other", "BarnLine"])
    }

    func testASlotOnlyOneWindowListsIsStillCollected() {
        let merged = HostedWindows.merge([
            [slot(10, 375, 796)],
            [slot(10, 375, 796, "BarnLine"), slot(30, 1213, 38)],
        ])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.last?.pid, 30)
    }

    func testIdentifiedIsTrueOnlyWhenEveryOneOfOursIsNamed() {
        let named = [slot(10, 375, 796, "BarnLine"), slot(20, 1179, 34)]
        let partly = [slot(10, 375, 796, "BarnLine"), slot(10, 698, 34), slot(20, 1179, 34)]
        XCTAssertTrue(HostedWindows.identified(named, for: 10))
        XCTAssertFalse(HostedWindows.identified(partly, for: 10))
        // Nothing of ours on the bar is not "identified": another window may
        // yet list the slot this one dropped.
        XCTAssertFalse(HostedWindows.identified([slot(20, 1179, 34)], for: 10))
    }
}
