// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BarnCore

final class HandleStyleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "barn.handlestyle.tests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToTheDoubleChevron() {
        XCTAssertEqual(HandleStyleStore.load(from: defaults), .doubleChevron)
    }

    func testRoundTripsTheBarn() {
        HandleStyleStore.save(.barn, to: defaults)
        XCTAssertEqual(HandleStyleStore.load(from: defaults), .barn)
    }

    func testRoundTripsTheChevron() {
        HandleStyleStore.save(.chevron, to: defaults)
        XCTAssertEqual(HandleStyleStore.load(from: defaults), .chevron)
    }

    func testUnknownValueFallsBackToTheDefault() {
        defaults.set("windmill", forKey: HandleStyleStore.defaultsKey)
        XCTAssertEqual(HandleStyleStore.load(from: defaults), .doubleChevron)
    }
}
