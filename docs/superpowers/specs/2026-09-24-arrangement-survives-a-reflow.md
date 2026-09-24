# A resolution change re-orders our own items, and the « comes back

Date: 2026-09-24
Status: fixed
Builds on: 2026-09-17-two-lines-and-collapse-design.md,
2026-09-22-agent-publishes-four-windows.md

## The symptom

The system « "kept coming back on its own", and the bar had a **huge empty
gap in the middle**, between the leftmost icons and the rest.

## What the bar actually looked like

The display had dropped from 2x to 1x (1600×900, same 1600 points wide).
Reading one agent window whole:

```
«=1037..1054
   410..444    Barn BarnHandle      ← left of everything, off the display
   444..490    UA Mixer Engine
   490..1030   Barn BarnLineB       ← 540pt line PLACED in the visible strip
  1062..1108   VPN & DNS
  ...
```

`BarnLine` (A) had no slot at all. So:

- **B was the gap.** A wide line is only ever invisible because it is
  dropped, or because it sits under the frontmost app's menus. Placed at
  490..1030 it is exactly what it is: 540 points of empty status item in
  the middle of the bar.
- **The handle was off the display again**, left of the wall.
- **A was gone**, and every width the hide computes is measured from A's
  right edge.

The agent re-places the whole bar on a resolution change and does not
hand the items back in the order it took them. Barn's read-back only ever
compared its own widths, so it nudged them 8pt at a time, four times, logged
"giving up", and left the system « on the bar — then did it again on the
next poll, for as long as the bar stayed that way.

## The rule that was missing

The three items work in one order only: **B, then A, then the handle.**
Every number in `HostedBar.split` assumes it. That is now a check of its
own, `HostedBar.arrangement(a:b:handle:)`, run on every read-back:

| state | verdict |
|---|---|
| A placed, B dropped, handle right of A | sound |
| A placed, B immediately left of A, handle right of A | sound (the settle) |
| A with no slot | broken — every width is a fallback |
| handle with no slot, or left of A | broken — the control is gone |
| B right of A | broken — B reaches into the icons |

Broken → re-settle, which is what a launch does: narrow, let the agent
re-place everything, drag B and the handle back beside A. Three tries; out
of them, Barn would rather show the icons than leave a wide line the agent
has placed, because a hole in the menu bar is the one failure that looks
like Barn broke it.

## And when the « is not ours to size away

With the lines where they belong and a « still up, the item in the band is
somebody's icon and no width of Barn's will move it. Barn now does what the
agent is doing, but into the barn: it hides the leftmost visible icon, the
same as ticking it off in Visible Icons, bounded by the existing collapse
limit of three per boundary.

## One window, whole

The four windows publish the same bar but are separate snapshots. Caught
mid-reflow on 2026-09-24 they gave four different positions for the same
icons, and merging them by position turned one icon into two — at both its
old and its new place. `HostedWindows.pickIndex` now takes the first window
that names our items and uses that one entire, « included.

## What is still true

The agent's overflow has no off switch. Barn cannot disable the «; it can
only make sure nothing is ever an overflow member. The one case it cannot
win is unchanged: an app whose menus run past about half the display leaves
a band no item can cross without starting inside it, and the « shows for
that app. Barn says so in the log rather than fighting it.
