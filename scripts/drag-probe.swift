// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

// Phase 0 gate (throwaway probe, kept for the record).
//
// Question: can we move a status item by synthesizing a Cmd-drag, and does the
// move persist? Everything in Task 7 (verified arranging) depends on the answer.
//
// The probe is self-verifying: it creates its own fixture item, reads its frame
// directly from the item's window (no AX needed), drags itself, and reads back.
//
// Run with Ice quit — Ice parks unknown items off-screen within ~2s, and an
// off-screen item cannot be pressed at all, since the cursor clamps to the screen.
//
//   swiftc -O -o /tmp/DragProbe scripts/drag-probe.swift && /tmp/DragProbe
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let item = NSStatusBar.system.statusItem(withLength: 48)
item.button?.title = "◆DRAG"

func log(_ s: String) { print(s); fflush(stdout) }

func itemFrame() -> CGRect? { item.button?.window?.frame }

/// Convert an AppKit point (origin bottom-left) to CoreGraphics global display
/// coordinates (origin top-left), which is what CGEvent expects.
func cgPoint(_ p: CGPoint) -> CGPoint {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGPoint(x: p.x, y: h - p.y)
}

func cmdDrag(from source: CGPoint, to target: CGPoint, steps: Int = 24) {
    guard let src = CGEventSource(stateID: .hidSystemState) else { return }
    // Keep the user's real mouse from fighting the synthetic drag.
    src.setLocalEventsFilterDuringSuppressionState(
        [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
        state: .eventSuppressionStateSuppressionInterval
    )

    func post(_ type: CGEventType, _ at: CGPoint) {
        guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                              mouseCursorPosition: at, mouseButton: .left) else { return }
        e.flags = .maskCommand
        e.post(tap: .cghidEventTap)
    }

    post(.mouseMoved, source)
    usleep(120_000)
    post(.leftMouseDown, source)
    usleep(120_000)
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        post(.leftMouseDragged, CGPoint(x: source.x + (target.x - source.x) * t, y: source.y))
        usleep(18_000)
    }
    usleep(120_000)
    post(.leftMouseUp, target)
}

log("probe: waiting for the fixture item to be placed…")

Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
    guard let before = itemFrame() else { log("FAIL: fixture item has no window"); NSApp.terminate(nil); return }
    log("before: x=\(Int(before.minX)) w=\(Int(before.width))")
    guard before.minX > 0 else {
        log("FAIL: fixture was parked off-screen (Ice still running?) — cannot press there")
        NSApp.terminate(nil); return
    }

    let cursorBefore = NSEvent.mouseLocation
    let source = cgPoint(CGPoint(x: before.midX, y: before.midY))
    // Drag 220pt to the left (toward the notch) — the direction arranging uses.
    let target = CGPoint(x: source.x - 220, y: source.y)
    log("dragging from x=\(Int(source.x)) to x=\(Int(target.x)) (cg y=\(Int(source.y)))")
    cmdDrag(from: source, to: target)

    Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
        guard let after = itemFrame() else { log("FAIL: no window after drag"); NSApp.terminate(nil); return }
        let moved = after.minX - before.minX
        log("after:  x=\(Int(after.minX)) w=\(Int(after.width))")
        log("RESULT: moved \(Int(moved))pt (asked for -220pt)")
        log(abs(moved) < 5 ? "VERDICT: drag did NOT move the item" : "VERDICT: drag moved the item")
        // Put the cursor back where the user left it.
        if let src = CGEventSource(stateID: .hidSystemState),
           let e = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                           mouseCursorPosition: cgPoint(cursorBefore), mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        NSApp.terminate(nil)
    }
}

app.run()
