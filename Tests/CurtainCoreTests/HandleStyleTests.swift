import XCTest
@testable import CurtainCore

final class HandleStyleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "curtain.handlestyle.tests"

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

    func testDefaultsToTheBarn() {
        XCTAssertEqual(HandleStyleStore.load(from: defaults), .barn)
    }

    func testRoundTripsTheChevron() {
        HandleStyleStore.save(.chevron, to: defaults)
        XCTAssertEqual(HandleStyleStore.load(from: defaults), .chevron)
    }

    func testUnknownValueFallsBackToTheBarn() {
        defaults.set("windmill", forKey: HandleStyleStore.defaultsKey)
        XCTAssertEqual(HandleStyleStore.load(from: defaults), .barn)
    }
}
