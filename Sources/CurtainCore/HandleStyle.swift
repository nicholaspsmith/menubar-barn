import Foundation

/// What the control in the menu bar looks like.
public enum HandleStyle: String, CaseIterable, Sendable {
    /// A small barn whose doors are shut while the curtain is drawn and open
    /// while the icons are revealed. The default: it is what the Menubarn
    /// library is named for.
    case barn
    /// The original chevron, pointing the way the icons will go.
    case chevron

    public var label: String {
        switch self {
        case .barn: return "Barn"
        case .chevron: return "Chevron"
        }
    }
}

/// Persistence for the chosen `HandleStyle`.
public enum HandleStyleStore {
    public static let defaultsKey = "handleStyle"

    /// Falls back to the barn when the key is absent or holds a value this
    /// build does not know.
    public static func load(from defaults: UserDefaults) -> HandleStyle {
        guard let raw = defaults.string(forKey: defaultsKey),
              let style = HandleStyle(rawValue: raw)
        else { return .barn }
        return style
    }

    public static func save(_ style: HandleStyle, to defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: defaultsKey)
    }
}
