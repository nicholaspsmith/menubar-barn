// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BarnCore

final class PanelOrderTests: XCTestCase {
    private struct App: Equatable {
        let key: String
        let name: String
    }

    private let apps = [
        App(key: "com.raycast.macos", name: "Raycast"),
        App(key: "net.mullvad.vpn", name: "Mullvad VPN"),
        App(key: "com.nicholaspsmith.KeyLight", name: "KeyLight"),
        App(key: "io.tailscale.ipn.macsys", name: "Tailscale"),
    ]

    private func ordered(by order: [String]) -> [String] {
        PanelOrderStore.ordered(apps, key: \.key, name: \.name, by: order).map(\.name)
    }

    func testNoSavedOrderIsAlphabeticalIgnoringCase() {
        XCTAssertEqual(ordered(by: []), ["KeyLight", "Mullvad VPN", "Raycast", "Tailscale"])
    }

    func testSavedOrderIsFollowed() {
        let order = ["io.tailscale.ipn.macsys", "com.raycast.macos", "com.nicholaspsmith.KeyLight", "net.mullvad.vpn"]
        XCTAssertEqual(ordered(by: order), ["Tailscale", "Raycast", "KeyLight", "Mullvad VPN"])
    }

    func testAppsNotInTheSavedOrderFollowItAlphabetically() {
        // Two apps were ordered; the other two launched later and take their
        // alphabetical place after the ordered ones.
        XCTAssertEqual(ordered(by: ["io.tailscale.ipn.macsys", "com.raycast.macos"]), ["Tailscale", "Raycast", "KeyLight", "Mullvad VPN"])
    }

    func testKeysInTheSavedOrderThatAreNotRunningAreIgnored() {
        XCTAssertEqual(ordered(by: ["com.gone.app", "net.mullvad.vpn"]), ["Mullvad VPN", "KeyLight", "Raycast", "Tailscale"])
    }

    func testRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "PanelOrderTests")!
        defaults.removePersistentDomain(forName: "PanelOrderTests")
        XCTAssertEqual(PanelOrderStore.load(from: defaults), [])
        PanelOrderStore.save(["b", "a"], to: defaults)
        XCTAssertEqual(PanelOrderStore.load(from: defaults), ["b", "a"])
        PanelOrderStore.save([], to: defaults)
        XCTAssertEqual(PanelOrderStore.load(from: defaults), [])
    }
}
