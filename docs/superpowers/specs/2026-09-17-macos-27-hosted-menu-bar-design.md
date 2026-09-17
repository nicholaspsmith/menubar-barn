# Barn on macOS 27 — hiding inside the hosted menu bar

Date: 2026-09-17
Status: approved, implementing

## What broke

macOS 27 (build 26A428) moved every status item into one process,
`MenuBarAgent` (`com.apple.MenuBarAgent`). Apps no longer own a window per
item; the agent composites the whole bar and lays items out itself. Two
consequences, both measured on this machine (external 1600×900pt display, no
notch):

1. **An over-long item is ejected, not laid out.** Barn's 2000pt line reads
   `w=2002` in Barn's own accessibility tree, but the agent's layout has no
   slot for it at all, so it pushes nothing. Every neighbour sits exactly where
   it would without Barn.
2. **Displaced items no longer slide off the left edge.** The agent lays the
   trailing items out right-to-left and gives each a *virtual* left edge. What
   happens to an item depends on that edge:

   | virtual left edge | outcome |
   |---|---|
   | ≥ the frontmost app's menu boundary | placed and drawn |
   | ≥ ~143pt, < the boundary | **overflowed**: no drawing, stacked against a system « button ("Show Hidden Menu Bar Items") |
   | < ~143pt | **ejected**: no slot, not in the « menu, gone from the bar |

   A slot ≥ half the display width (800pt here; 796 fine, 836 ejected) is
   ejected regardless of where it sits. The ~143pt floor is the same whether
   Finder (menus end at 392) or Terminal (562) is frontmost, so it is not the
   app menu; it is treated as a measured constant with a verify-and-shrink loop
   behind it rather than trusted.

Everything else still works. An app's own `AXExtrasMenuBar` still lists its
item while ejected, and the item's menu can still be read and pressed through
it, so the panel is unaffected. `NSStatusItem Preferred Position` is honoured
for a brand-new autosave name, measured leftwards from the trailing end.

## Probe findings

- A 30pt probe placed between Mullvad and Media Tracking Killer, widened to
  300pt in one step: the four items to its left collapsed onto x≈734–746 (the
  « button at 763–780), the items to its right did not move. Under Finder,
  whose menus are shorter, only three of the four overflowed — the overflow set
  depends on the frontmost app, so it cannot be what Barn relies on.
- Widened to 470–590pt, the leftmost of those four vanished one by one: no
  slot in the agent's tree, nothing in the « menu. At 621pt (left edge 143)
  the probe itself still had a slot; at 622pt (left edge 142) it was ejected.
- The « button appears whenever anything is overflowed *or* ejected, drawn
  either just left of the leftmost placed item or, when there is no room
  there, over the right end of that item. With Barn's line that means it sits
  immediately left of the handle. It cannot be suppressed.
- The per-app accessibility frames are no longer trustworthy: three items
  created by one process reported one frame. Only the agent's tree says where
  a slot really is.

## Design

Barn keeps its mechanism — the line's width displaces the block — and reads
the truth from the agent instead of from each app.

**Width.** The line is widened to
`min(displayWidth / 2 − 16 − margin, lineRightEdge − floor − margin)`, where
`lineRightEdge` is the line's own slot as the agent lays it out while narrow.
The line's left edge then lands just above the floor, so the first hidden
icon's virtual edge is below it and the whole block to the left is ejected —
there is no longer a capacity limit on the hidden block. On a bar where the
half-width cap wins, the nearest icon or two overflow into the « menu instead
of being ejected; either way they are off the bar. After widening, Barn reads
the agent's layout back: a line with no slot was ejected (the floor was
wrong for this display), so it shrinks by a step and tries again. The
re-hide after a reveal reads the line's edge while the yielding siblings are
still narrow, so it overshoots by their width and the first retry is the one
that lands — measured: 780 ejected, 748 placed at 157..921.

**Reading the bar.** On 27, `AXMenuBar.items()` walks the agent's window: one
slot per placed or overflowed item, each carrying the owning app's pid. An
app that publishes a status item in its own tree but has no slot is ejected;
one whose slot overlaps the « button is overflowed. Both are reported as
`.hidden` with the app's own width and no usable x. The « button is the
window child of role `AXButton` owned by the agent, so its localized
description is never consulted.

**What stays.** The two-item design, the panel, the live AX menus, the yield
protocol during a reveal, and the pre-27 code paths. The switch is the agent
itself — `com.apple.MenuBarAgent` running — rather than an OS version check,
since the mechanism belongs to that process. The notch dead-zone arithmetic
is left in place for older systems; on 27 the agent manages the notch itself.

**What goes.** The capacity refusals ("no room to show") are skipped on 27:
an icon that does not fit overflows into the system « menu, it is not
stranded, and refusing would be wrong.
