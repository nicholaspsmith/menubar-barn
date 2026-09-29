// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import XCTest
@testable import BarnCore

/// A menu tracks the mouse in the event-tracking run-loop mode. Work that
/// opens a modal (an alert) must wait until the loop is back in the default
/// mode, or the menu never finishes closing and swallows every click.
final class AfterMenuClosesTests: XCTestCase {
    func testDoesNotRunWhileAMenuIsTracking() {
        var ran = false
        afterMenuCloses { ran = true }
        RunLoop.current.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.1))
        XCTAssertFalse(ran)
    }

    func testRunsOnceTheRunLoopIsBackInTheDefaultMode() {
        var ran = false
        afterMenuCloses { ran = true }
        RunLoop.current.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.1))
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        XCTAssertTrue(ran)
    }
}
