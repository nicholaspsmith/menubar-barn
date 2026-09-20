// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// What ends a reveal.
public enum RevealMode: String, CaseIterable, Sendable {
    /// Stays revealed until clicked again. The chevron flips to show which way
    /// round things are.
    case toggle
    /// Puts itself away after a fixed interval.
    case timeout

    public var label: String {
        switch self {
        case .toggle: return "Click to Hide Again"
        case .timeout: return "Hide Automatically"
        }
    }
}

/// Persistence for the chosen `RevealMode`.
public enum RevealModeStore {
    public static let defaultsKey = "revealMode"

    /// How long a `.timeout` reveal lasts.
    public static let timeoutDuration: TimeInterval = 15

    /// Falls back rather than trapping when the key is absent or holds something
    /// this build does not know, so downgrading after a future version adds a
    /// mode degrades gracefully.
    public static func load(from defaults: UserDefaults) -> RevealMode {
        guard let raw = defaults.string(forKey: defaultsKey),
              let mode = RevealMode(rawValue: raw)
        else { return .toggle }
        return mode
    }

    public static func save(_ mode: RevealMode, to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }
}
