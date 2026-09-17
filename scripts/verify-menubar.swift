// Reports what the menu bar looks like and flags anything stranded.
//
// Reads AXExtrasMenuBar, never AXMenuBar: for a regular app the latter is the
// app menu (Apple, File, Edit…), whose items all sit at the left of the screen
// and read as stranded icons. Same trap the app itself had to avoid.
//
// Exits 1 if any icon has a slot it cannot draw in.
import AppKit
import ApplicationServices

func element(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &value) == .success,
          let kids = value as? [AXUIElement]
    else { return [] }
    return kids
}

func axValue<T>(_ e: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    let out = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { out.deallocate() }
    guard AXValueGetValue(value as! AXValue, type, out) else { return nil }
    return out.pointee
}

guard AXIsProcessTrusted() else {
    print("Accessibility not granted to this terminal — cannot read the menu bar.")
    exit(2)
}

let screen = NSScreen.main
let usableMinX = screen?.auxiliaryTopRightArea?.minX ?? 0
let deadZone = usableMinX > 0 ? usableMinX + 40 : 0

print("usable area starts at x=\(Int(usableMinX))" + (deadZone > 0 ? "  (dead zone below x=\(Int(deadZone)))" : "  (no notch)"))
print("")

var visible: [String] = []
var hidden: [String] = []
var stranded: [(String, CGFloat)] = []

func name(of pid: pid_t) -> String {
    NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
}

/// Which apps say they have a status item at all. On every macOS this is the
/// right list of *owners*; before 27 the frames are right too.
var claimed: [pid_t: [(CGFloat, CGFloat)]] = [:]
for app in NSWorkspace.shared.runningApplications {
    guard app.activationPolicy != .prohibited, !app.isTerminated else { continue }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 0.4)
    guard let bar = element(appElement, "AXExtrasMenuBar") else { continue }
    for item in children(bar) {
        guard let position: CGPoint = axValue(item, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(item, kAXSizeAttribute, .cgSize),
              size.width > 0
        else { continue }
        claimed[app.processIdentifier, default: []].append((position.x, size.width))
    }
}

// macOS 27: MenuBarAgent lays the bar out and its window is the only tree
// whose positions are real. An app with an item but no slot has been ejected
// (Barn's doing, or the bar's own overflow); a slot on the « button is in the
// system overflow. Both are off the bar.
let agent = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.MenuBarAgent" }
let controlCenter = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.controlcenter" }
if let agent {
    print("hosted bar (macOS 27): reading MenuBarAgent's layout")
    let agentElement = AXUIElementCreateApplication(agent.processIdentifier)
    AXUIElementSetMessagingTimeout(agentElement, 1.0)
    var raw: CFTypeRef?
    AXUIElementCopyAttributeValue(agentElement, kAXWindowsAttribute as CFString, &raw)
    guard let window = (raw as? [AXUIElement])?.first else {
        print("MenuBarAgent's window is not readable — is Accessibility granted?")
        exit(2)
    }
    var chevron: (CGFloat, CGFloat)?
    var slots: [(pid_t, CGFloat, CGFloat)] = []
    for child in children(window) {
        guard let position: CGPoint = axValue(child, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(child, kAXSizeAttribute, .cgSize) else { continue }
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
        var owner: pid_t = 0
        if (roleValue as? String) == (kAXButtonRole as String), AXUIElementGetPid(child, &owner) == .success, owner == agent.processIdentifier {
            chevron = (position.x, size.width)
            continue
        }
        guard let item = children(child).first, AXUIElementGetPid(item, &owner) == .success,
              owner != agent.processIdentifier else { continue }
        slots.append((owner, position.x, size.width))
    }
    let ownPID = NSWorkspace.shared.runningApplications.first { $0.localizedName == "Barn" }?.processIdentifier
    for (pid, x, width) in slots where pid != ownPID {
        let overflowed = chevron.map { x < $0.0 + $0.1 && x + width > $0.0 } ?? false
        if overflowed { hidden.append(name(of: pid) + " (system overflow)") } else { visible.append(name(of: pid)) }
    }
    for (pid, items) in claimed where pid != ownPID && pid != agent.processIdentifier && pid != controlCenter?.processIdentifier {
        let placed = slots.filter { $0.0 == pid }.count
        for _ in items.dropFirst(placed) { hidden.append(name(of: pid)) }
    }
    if let chevron { print("system « button at x=\(Int(chevron.0))") }
    if let ownPID, let line = slots.first(where: { $0.0 == ownPID && $0.2 > 100 }) {
        print("Barn's line spans x=\(Int(line.1))..\(Int(line.1 + line.2))")
    } else if ownPID != nil {
        print("Barn's line is narrow or ejected")
    }
} else {
    for (pid, items) in claimed {
        let owner = name(of: pid)
        // Barn's own line is a deliberately enormous item lying off to the left;
        // classifying it alongside real icons would report the mechanism as a fault.
        guard owner != "Barn" else { continue }
        for (x, width) in items {
            if x + width <= 0 {
                hidden.append(owner)
            } else if x < deadZone {
                stranded.append((owner, x))
            } else {
                visible.append(owner)
            }
        }
    }
}

// An app with several items says nothing extra by being listed several times.
visible = Array(Set(visible))
hidden = Array(Set(hidden))

for name in visible.sorted() { print("  visible   \(name)") }
for name in hidden.sorted() { print("  hidden    \(name)") }
for (name, x) in stranded.sorted(by: { $0.0 < $1.0 }) {
    print("  STRANDED  \(name)  at x=\(Int(x)) — has a slot, draws nothing")
}

print("")
print("visible: \(visible.count)   hidden: \(hidden.count)   stranded: \(stranded.count)")
print("")

for name in ["Barn", "KeyLight", "VPN & DNS", "Battery Time", "Process Monitor"] {
    let running = NSWorkspace.shared.runningApplications.contains { $0.localizedName == name }
    print(running ? "  running      \(name)" : "  NOT RUNNING  \(name)")
}
let ice = NSWorkspace.shared.runningApplications.contains { $0.localizedName == "Ice" }
print(ice ? "  WARNING      Ice is running and will fight Barn" : "  absent       Ice")

print("")
if stranded.isEmpty {
    print("Nothing stranded.")
} else {
    print("\(stranded.count) icon(s) stranded — ⌘-drag them right, or use Manage Icons.")
    exit(1)
}
