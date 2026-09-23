# The agent publishes four windows, and only one of them is named

Date: 2026-09-22
Status: fixed
Builds on: 2026-09-17-macos-27-hosted-menu-bar-design.md,
2026-09-17-two-lines-and-collapse-design.md

## The symptom

Both of the things the two-lines work was for had quietly stopped
happening: the **system « was on the bar permanently**, and **Barn's own
barn-red « was not on it at all**. Everything else looked healthy —
`verify-menubar.sh` reported nothing stranded, the right ten icons hidden,
the right six visible.

## What the agent's tree actually looks like

`AXUIElementCopyAttributeValue(agent, kAXWindowsAttribute)` returns **four**
windows, not one. All four are `AXWindow`/`AXDialog` at 0,0 sized to the
display (1600×30 here), and all four list the same twelve children in the
same places.

They differ in what a slot's child *is*:

| window | slot's first child | `AXIdentifier` |
|---|---|---|
| 0 | the owning `AXApplication` | none |
| **1** | the status item's **`AXButton`** | **set** |
| 2 | the owning `AXApplication` | none |
| 3 | the owning `AXApplication` | none |

Measured four times in a row, 2026-09-22: window 1 every time, 7 of its 11
slots carrying buttons (the other four are the agent's own groups — clock,
Control Center, Wi‑Fi, Spotlight), and it was the only window on the whole
bar to carry an identifier at all, because Barn is the only app that sets
one.

Which index it is is undocumented and not worth trusting. Read the windows
in turn and merge: frames and order from the first window that lists a slot,
the identifier from whichever one carries it.

## Why one bad window broke both halves

`AXHostedBar.layout()` read `windows.first`. Window 0 names nothing, so
every `ownSlot(_:)` lookup returned nil, and three things followed:

1. **`hideLine` lost A's right edge.** `rightEdge` falls back to the display
   width, so A was sized from 1600 instead of its real 1171 — about 430pt
   too long. Its left edge landed at 375, inside the band (142–562 for
   iTerm2 in front), which is precisely the definition of an overflow
   member: **the agent showed its «**, exactly the thing Barn exists to
   replace.
2. **The read-back could never pass.** `verifyHostedHide` wants A placed, B
   dropped, no «; it saw `A placed=false` forever, burned its four retries
   and logged "giving up" on every hide, every poll, for days.
3. **`placeHandleBesideLine` never ran.** It needs A's slot and the
   handle's. The agent here ranks the handle *left* of the lines — at the
   far end of the hidden block, x=698 with everything narrow — so A's own
   width pushed it off the display. That repair existed and was correct; it
   simply could not see the bar it was repairing.

So a single misread window hid Barn's own control behind Barn's own wall
and handed the overflow back to the system.

## The fix

- `AXHostedBar.layout()` reads every window and merges them
  (`BarnCore.HostedWindows`), stopping as soon as every slot of our own pid
  has a name — normally after the second window.
- The hide's read-back now also checks the handle has a slot at all, and
  re-settles if it does not: narrow, let the agent re-place everything,
  drag the handle back beside A. `placeHandleBesideLine` cannot do this
  itself — it drags the handle from where it sits, and an item with no slot
  has nowhere to drag from. Bounded to three tries, because a re-settle
  flashes the hidden block back for a moment.
- `verify-menubar.sh` merges the windows too, prints where the handle is,
  and now exits 1 on a system « or a missing handle instead of calling the
  bar clean.

## After

```
hosted bar (macOS 27): reading MenuBarAgent's layout
Barn's line spans x=626..1145
Barn's handle at x=1145
visible: 6   hidden: 10   stranded: 0
Nothing stranded.
```

with `hosted hide: A ends at x=1145, menus end at 562, floor 142` and
`hosted hide: clean after 1 retries` in the log, no system « on the bar, and
the barn-red « drawn at the left edge of the visible icons.
