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
///
/// They are separate snapshots, though, so the named one is taken whole
/// rather than merged with the rest: measured 2026-09-24 mid-reflow, the four
/// windows gave four different positions for the same icons.
final class HostedWindowPickTests: XCTestCase {
    private func slot(_ pid: pid_t, _ x: CGFloat, _ width: CGFloat, _ identifier: String? = nil) -> HostedSlotReading {
        HostedSlotReading(pid: pid, frame: ItemFrame(minX: x, width: width), identifier: identifier)
    }

    func testTheNamedWindowIsTheOneUsed() {
        let anonymous = [slot(10, 375, 796), slot(20, 1179, 34)]
        let named = [slot(10, 375, 796, "BarnLine"), slot(20, 1179, 34)]
        XCTAssertEqual(HostedWindows.pickIndex([anonymous, named, anonymous], naming: 10), 1)
    }

    func testWithNothingNamedTheFirstWindowThatListedAnythingWins() {
        let anonymous = [slot(10, 375, 796), slot(20, 1179, 34)]
        XCTAssertEqual(HostedWindows.pickIndex([[], anonymous, anonymous], naming: 10), 1)
    }

    func testNoWindowListedAnything() {
        XCTAssertNil(HostedWindows.pickIndex([[], []], naming: 10))
    }

    func testAWindowNamingOnlySomeOfOursIsNotTheNamedOne() {
        // Barn has three items; a window that named one and lost the others
        // is mid-reflow, and the next one may have them all.
        let partial = [slot(10, 375, 796, "BarnLine"), slot(10, 698, 34)]
        let whole = [slot(10, 375, 796, "BarnLine"), slot(10, 698, 34, "BarnHandle")]
        XCTAssertEqual(HostedWindows.pickIndex([partial, whole], naming: 10), 1)
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
