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

for app in NSWorkspace.shared.runningApplications {
    guard app.activationPolicy != .prohibited, !app.isTerminated else { continue }
    let name = app.localizedName ?? "Unknown"
    // Barn's own line is a deliberately enormous item lying off to the left;
    // classifying it alongside real icons would report the mechanism as a fault.
    guard name != "Barn" else { continue }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 0.4)
    guard let bar = element(appElement, "AXExtrasMenuBar") else { continue }
    for item in children(bar) {
        guard let position: CGPoint = axValue(item, kAXPositionAttribute, .cgPoint),
              let size: CGSize = axValue(item, kAXSizeAttribute, .cgSize),
              size.width > 0
        else { continue }
        if position.x + size.width <= 0 {
            hidden.append(name)
        } else if position.x < deadZone {
            stranded.append((name, position.x))
        } else {
            visible.append(name)
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
