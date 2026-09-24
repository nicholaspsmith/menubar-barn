// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The order the panel lists menu-bar apps in.
///
/// Empty means alphabetical, which is also the default. A saved order is a
/// list of app keys (bundle identifier, or name for an app without one); apps
/// it does not mention take their alphabetical place after the ones it does,
/// so a newly installed app never vanishes to the bottom in some arbitrary spot,
/// and keys for apps that are not running are simply skipped.
public enum PanelOrderStore {
    public static let defaultsKey = "panelOrder"

    public static func load(from defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    /// Saving an empty order removes the key: alphabetical is the absence of
    /// a preference, not a preference of its own.
    public static func save(_ order: [String], to defaults: UserDefaults) {
        if order.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(order, forKey: defaultsKey)
        }
    }

    public static func ordered<T>(_ items: [T], key: (T) -> String, name: (T) -> String, by order: [String]) -> [T] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let alphabetical = items.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
        let ranked = alphabetical.filter { rank[key($0)] != nil }.sorted { rank[key($0)]! < rank[key($1)]! }
        let unranked = alphabetical.filter { rank[key($0)] == nil }
        return ranked + unranked
    }
}
