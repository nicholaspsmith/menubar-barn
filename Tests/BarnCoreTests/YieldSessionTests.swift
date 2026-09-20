// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BarnCore

final class YieldSessionTests: XCTestCase {
    func testNotExpiredBeforeTTL() {
        let s = YieldSession(token: "t", ttl: 8, startedAt: 100)
        XCTAssertFalse(s.isExpired(at: 107))
    }

    func testExpiredAtTTL() {
        let s = YieldSession(token: "t", ttl: 8, startedAt: 100)
        XCTAssertTrue(s.isExpired(at: 108))
    }

    func testExtendingPushesTheDeadlineOut() {
        let s = YieldSession(token: "t", ttl: 8, startedAt: 100).extended(at: 105, by: 8)
        XCTAssertFalse(s.isExpired(at: 112))
        XCTAssertTrue(s.isExpired(at: 113))
    }

    func testExtendingKeepsTheToken() {
        // The token identifies the peek across processes; a restore carrying a
        // stale token must not cancel a peek that has since been extended.
        let s = YieldSession(token: "abc", ttl: 8, startedAt: 100).extended(at: 105, by: 8)
        XCTAssertEqual(s.token, "abc")
    }
}
