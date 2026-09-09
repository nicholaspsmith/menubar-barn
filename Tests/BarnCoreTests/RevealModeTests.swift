import XCTest
@testable import BarnCore

final class RevealModeTests: XCTestCase {
    /// An isolated defaults domain, so the tests never touch the real Barn
    /// preferences.
    private var defaults: UserDefaults!
    private let suite = "barn.revealmode.tests"

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

    func testDefaultsToToggle() {
        // Clicking to put the icons back is the predictable behaviour; a timeout
        // that yanks the bar out from under you is opt-in.
        XCTAssertEqual(RevealModeStore.load(from: defaults), .toggle)
    }

    func testRoundTrips() {
        RevealModeStore.save(.timeout, to: defaults)
        XCTAssertEqual(RevealModeStore.load(from: defaults), .timeout)
    }

    func testUnknownStoredValueFallsBack() {
        // Downgrading after a future version adds a mode must not trap.
        defaults.set("interpretive-dance", forKey: RevealModeStore.defaultsKey)
        XCTAssertEqual(RevealModeStore.load(from: defaults), .toggle)
    }

    func testEveryModeHasALabel() {
        for mode in RevealMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
        }
    }
}
