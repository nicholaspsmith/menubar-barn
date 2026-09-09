import Foundation

/// Where an icon sat just before it was hidden, so unhiding can put it back.
///
/// Two clues rather than one. A remembered x is only meaningful against the
/// layout it was measured in, and the bar reflows constantly; the icon that sat
/// to its *right* is a far steadier landmark, since relative order survives
/// everything except that neighbour itself disappearing.
public struct HidePlacement: Codable, Equatable, Sendable {
    /// Identifier of the icon that sat immediately to the right.
    public let rightNeighbour: String?
    /// The icon's own x when it was hidden, as a fallback.
    public let x: CGFloat

    public init(rightNeighbour: String?, x: CGFloat) {
        self.rightNeighbour = rightNeighbour
        self.x = x
    }
}

public enum PlacementStore {
    public static let defaultsKey = "hidePlacements"

    public static func save(_ placement: HidePlacement, for id: String, to defaults: UserDefaults) {
        var all = load(from: defaults)
        all[id] = placement
        write(all, to: defaults)
    }

    public static func placement(for id: String, in defaults: UserDefaults) -> HidePlacement? {
        load(from: defaults)[id]
    }

    public static func forget(_ id: String, in defaults: UserDefaults) {
        var all = load(from: defaults)
        all.removeValue(forKey: id)
        write(all, to: defaults)
    }

    private static func load(from defaults: UserDefaults) -> [String: HidePlacement] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: HidePlacement].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func write(_ all: [String: HidePlacement], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

public enum DropTarget {
    /// How far left of the remembered neighbour to release, so the icon settles
    /// into the gap on that neighbour's left rather than swapping with it.
    public static let neighbourGap: CGFloat = 6

    /// Where to release a restored icon so it lands where it used to be.
    ///
    /// Prefers the remembered neighbour, falls back to the remembered x, and
    /// finally to whatever the caller offers — an icon has to go *somewhere*, and
    /// arriving in the wrong place beats not arriving.
    /// - Parameter floor: the smallest x that counts as "across the line".
    ///   A remembered clue that resolves left of it would drop the icon back
    ///   into the hidden block — which is exactly what happened on 2026-09-06,
    ///   when the remembered neighbour was itself a hidden item — so such clues
    ///   are ignored in favour of the fallback.
    public static func x(
        for placement: HidePlacement?,
        neighbour: ItemFrame?,
        fallback: CGFloat,
        floor: CGFloat = 0
    ) -> CGFloat {
        if let neighbour, neighbour.minX - neighbourGap > floor { return neighbour.minX - neighbourGap }
        if let placement, placement.x > floor { return placement.x }
        return fallback
    }
}
