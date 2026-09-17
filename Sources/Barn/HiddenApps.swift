import AppKit
import BarnCore

/// An app whose status icon is currently parked off-screen.
struct HiddenApp {
    let name: String
    let pid: pid_t
    let icon: NSImage?
}

enum HiddenApps {
    /// Apps Barn is currently hiding, one entry each.
    ///
    /// `.hidden` means pushed clear off the left edge — deliberately out of the
    /// way. Items merely resting in the notch are `.deadZone`: stranded rather
    /// than hidden, and the watchdog's business, not the panel's.
    static func current(in geometry: MenuBarGeometry, ownPID: pid_t) -> [HiddenApp] {
        var seen = Set<pid_t>()
        return AXMenuBar.items()
            .filter { $0.pid != ownPID }
            .filter { $0.placement(in: geometry) == .hidden }
            .filter { seen.insert($0.pid).inserted }
            .map { item in
                HiddenApp(
                    name: item.name,
                    pid: item.pid,
                    icon: NSRunningApplication(processIdentifier: item.pid)?.icon
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
