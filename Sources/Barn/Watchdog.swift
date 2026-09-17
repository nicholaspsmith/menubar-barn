import AppKit
import BarnCore

/// Names icons that have a slot but nowhere useful to be.
///
/// This exists because of 2026-08-16: KeyLight's icon "disappeared" while the app
/// was perfectly healthy — it had simply been placed at x=837, in the sliver
/// beside the notch, where macOS gives an item a slot and draws nothing. Ice put
/// it there and never checked. Nothing tells the user; the icon is just gone.
///
/// Barn cannot always fix that (an item right of the line is beyond our
/// reach), but it can always *say so*, and being told is the entire difference.
enum Watchdog {
    /// Items sitting where the user can neither see nor click them.
    ///
    /// Every `.deadZone` item counts, wherever it sits relative to our line. An
    /// earlier version only looked to the right of the line, reasoning that
    /// anything left of it was hidden on purpose — and promptly missed a real
    /// case: an icon moved back across the line landed at x=831, invisible,
    /// overlapping the line's own span. Deliberately hidden is `.hidden`, off the
    /// left edge entirely; anything merely lost in the notch is worth saying out
    /// loud.
    static func stranded(in geometry: MenuBarGeometry, ownPID: pid_t) -> [MenuBarItem] {
        var seen = Set<String>()
        return AXMenuBar.items()
            .filter { $0.pid != ownPID }
            .filter { $0.placement(in: geometry) == .deadZone }
            // One warning per app: several items from one app say nothing extra.
            .filter { seen.insert($0.name).inserted }
    }
}
