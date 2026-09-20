// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// What the control in the menu bar looks like.
public enum HandleStyle: String, CaseIterable, Sendable {
    /// The agent's own « — the button macOS 27 shows for its overflow —
    /// drawn in barn red. The default: Barn stands in for that overflow,
    /// so its control sits where the user has learned to look for one.
    case doubleChevron
    /// A barn whose doors are shut while the icons are hidden and open
    /// while the icons are revealed. What the Menubarn library is named for.
    case barn
    /// The original chevron, pointing the way the icons will go.
    case chevron

    public static let `default`: HandleStyle = .doubleChevron

    public var label: String {
        switch self {
        case .doubleChevron: return "Double Chevron"
        case .barn: return "Barn"
        case .chevron: return "Chevron"
        }
    }
}

/// Persistence for the chosen `HandleStyle`.
public enum HandleStyleStore {
    public static let defaultsKey = "handleStyle"

    /// Falls back to the default when the key is absent or holds a value
    /// this build does not know.
    public static func load(from defaults: UserDefaults) -> HandleStyle {
        guard let raw = defaults.string(forKey: defaultsKey),
              let style = HandleStyle(rawValue: raw)
        else { return .default }
        return style
    }

    public static func save(_ style: HandleStyle, to defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: defaultsKey)
    }
}
