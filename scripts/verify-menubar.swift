// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

// Reports what the menu bar looks like and flags anything stranded.
//
// Reads AXExtrasMenuBar, never AXMenuBar: for a regular app the latter is the
// app menu (Apple, File, Edit…), whose items all sit at the left of the screen
// and read as stranded icons. Same trap the app itself had to avoid.
//
// Exits 1 if any icon has a slot it cannot draw in, if the system « is
// showing, or if Barn's own handle is off the bar.
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
/// Things that are wrong but are nobody's slot — the system « showing, or
/// Barn's own handle missing from the bar.
var faults: [String] = []

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
    guard let windows = raw as? [AXUIElement], !windows.isEmpty else {
        print("MenuBarAgent's window is not readable — is Accessibility granted?")
        exit(2)
    }
    var chevron: (CGFloat, CGFloat)?
    var slots: [(pid: pid_t, x: CGFloat, width: CGFloat, identifier: String?)] = []
    // The agent publishes the same bar as several windows, and only one of
    // them hands back the apps' status-item *buttons* — the others answer
    // with the owning application element, which carries no identifier. Read
    // them all and merge, or Barn's own items come back anonymous and its
    // handle cannot be told from its line. Measured 2026-09-22: window 1 of
    // four had the buttons, and reading only the first is the bug that left
    // the system « on the bar with no barn-red one beside it.
    for window in windows {
        for child in children(window) {
            guard let position: CGPoint = axValue(child, kAXPositionAttribute, .cgPoint),
                  let size: CGSize = axValue(child, kAXSizeAttribute, .cgSize) else { continue }
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            var owner: pid_t = 0
            if (roleValue as? String) == (kAXButtonRole as String), AXUIElementGetPid(child, &owner) == .success, owner == agent.processIdentifier {
                chevron = chevron ?? (position.x, size.width)
                continue
            }
            guard let item = children(child).first, AXUIElementGetPid(item, &owner) == .success,
                  owner != agent.processIdentifier else { continue }
            var identifierValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
            let identifier = identifierValue as? String
            if let index = slots.firstIndex(where: { $0.pid == owner && $0.x == position.x && $0.width == size.width }) {
                if slots[index].identifier == nil { slots[index].identifier = identifier }
            } else {
                slots.append((owner, position.x, size.width, identifier))
            }
        }
    }
    let ownPID = NSWorkspace.shared.runningApplications.first { $0.localizedName == "Barn" }?.processIdentifier
    for (pid, x, width, _) in slots where pid != ownPID {
        let overflowed = chevron.map { x < $0.0 + $0.1 && x + width > $0.0 } ?? false
        if overflowed { hidden.append(name(of: pid) + " (system overflow)") } else { visible.append(name(of: pid)) }
    }
    for (pid, items) in claimed where pid != ownPID && pid != agent.processIdentifier && pid != controlCenter?.processIdentifier {
        let placed = slots.filter { $0.pid == pid }.count
        for _ in items.dropFirst(placed) { hidden.append(name(of: pid)) }
    }
    if let chevron {
        print("system « button at x=\(Int(chevron.0))")
        if ownPID != nil { faults.append("the system « is showing — Barn is meant to be standing in for it") }
    }
    if let ownPID {
        let ours = slots.filter { $0.pid == ownPID }
        if let line = ours.first(where: { $0.identifier == "BarnLine" }) ?? ours.first(where: { $0.width > 100 }) {
            print("Barn's line spans x=\(Int(line.x))..\(Int(line.x + line.width))")
        } else {
            print("Barn's line is narrow or ejected")
        }
        // The handle is the only control Barn has. Off the bar it is not an
        // inconvenience, it is the app gone: nothing left to click.
        if let handle = ours.first(where: { $0.identifier == "BarnHandle" }) {
            print("Barn's handle at x=\(Int(handle.x))")
        } else if ours.contains(where: { $0.identifier != nil }) {
            print("Barn's handle has no slot — its own line is hiding its control")
            faults.append("Barn's handle is off the bar")
        } else {
            print("Barn's items came back unnamed — the agent handed back no buttons")
        }
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
for fault in faults { print("FAULT  \(fault)") }
if stranded.isEmpty, faults.isEmpty {
    print("Nothing stranded.")
    exit(0)
}
if !stranded.isEmpty {
    print("\(stranded.count) icon(s) stranded — ⌘-drag them right, or use Manage Icons.")
}
exit(1)
