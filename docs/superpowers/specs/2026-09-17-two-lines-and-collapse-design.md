# Two lines, no system «, and collapse-on-overflow

Date: 2026-09-17
Status: approved, implementing
Builds on: 2026-09-17-macos-27-hosted-menu-bar-design.md

## Goal

On macOS 27 Barn should take the place of the agent's own overflow: the
system « must not appear while Barn runs, Barn's handle should look like that
« (in barn red), and when the bar fills up Barn — not the agent — should be
the one that collapses the leftmost icons.

## What the agent does, measured

The agent gives every trailing item a virtual left edge (laid out
right-to-left) and sorts it into one of three bands:

| virtual left edge | outcome |
|---|---|
| ≥ T, the frontmost app's last menu title plus ~24–48pt | placed |
| in [F, T) | **overflow member**: stacked on the « if its right edge is left of T, placed-but-crossing otherwise; either way the « is shown |
| < F | dropped silently — no slot, no « |

Both edges belong to the frontmost app. F is its *name* — the second title,
after the Apple menu — plus ~33pt: Terminal (name to 120) drops at ~154,
Zen (88) at ~124, Finder (105) at ~136, iTerm2 (109) at ~142, all with the
same probe. The 143 in the earlier spec was iTerm2's.

A slot ≥ half the display width is dropped regardless. The « is drawn only
when the overflow band is non-empty. That is the whole trick: with Barn's
single line the line itself sat in the band (left edge 165), so the « was
shown even though the hidden icons were all below F. A line whose own left
edge is below F is dropped too — but keeps pushing, as long as its slot
stays under half the display (measured: widths 630–750 on a right edge of 780
hid five icons with no «; 790 hit the half cap and everything came back).

Two probe items chained — A 205pt placed at 600..821 with Terminal's menus
ending at 562, B 440pt with its left edge at 130 — hid everything left of B
with no « (2026-09-17, `pair-adjacent.png`). An item sitting *between* the
two lands in the band and brings the « back.

## Design

**Two lines.** `A` (autosave `BarnLine`, the existing item) and `B`
(`BarnLineB`, new), adjacent, B immediately left of A. When hiding:

- A's left edge is aimed at `T + 56`; its width is `R − 16 − Aleft`,
  where `R` is A's slot's right edge as the agent lays it out.
- B's left edge is aimed at `F − 16`; its width is `Aleft − 16 − Bleft`.
- Each width is capped under the half-display cliff. If the cap binds on B
  (Aleft ≳ 943 on a 1600pt bar — an app with a ~900pt menu bar) B lands in
  the band and the « shows; nothing better is possible with two items.

`T` and `F` are read from the frontmost app's `AXMenuBar` and re-read on
`NSWorkspace.didActivateApplicationNotification` and every poll; only the
split moves — two length assignments, no drags, no reveal. Measured: Terminal
A=543/B=265, Finder 521/294, Zen 307/525, each clean on the first try.
After each application Barn reads the agent's layout back: an « present, or
B with a slot, means the numbers were wrong for this bar; A's target moves
right by 16 and B's left by 8 and it tries again, a few times.

**The handle.** New `HandleStyle.doubleChevron`, the default: « in barn
red, drawn on the 17.5×27 geometry of the agent's own button, flipping to »
while the panel is open or the block revealed. Barn and chevron stay
selectable. On launch, if anything sits between A and the handle, the handle
is dragged to A's right so it reads as the bar's «.

**Collapse.** The visible set fits when `R − 17 ≥ T + 56` (A needs at
least its narrow slot right of T). When it does not — a wider-menu app came
to the front — Barn hides the leftmost icon the agent still has a slot for
(reveal, ⌘-drag across B, re-hide — the existing arrange path) and checks
again, up to three times per app, and never within two seconds of a
keystroke. The move is persistent, like any hide, and the icon is listed in
the panel with its live menu. It is not put back automatically when room
returns: putting it back needs a reveal, and a reveal on every app switch
would be worse than the native behaviour it replaces. Visible Icons puts it
back.

**Room to arrange.** A drag is deterministic only while everything it
touches is placed. When the revealed bar does not fit the frontmost app's
menus, the agent stacks the leading items on its « at one set of
coordinates, and a drag there grabs and drops whatever it likes: the first
collapse of KeyLight took Rectangle and Claude Usage with it, and a direct
⌘-drag of a visible icon into the dropped region reordered half the bar. So
if the settled reveal shows a «, Barn takes the menu bar for itself — a
regular app for a moment, whose bar is the one word "Barn" — lets the agent
lay everything out, arranges, and hands focus back to the app that had it.
About a second and a half of borrowed focus, only when the bar would not
otherwise fit.

**Where two lines run out.** B is capped under half the display. When the
band `[F, T + 56)` is wider than that — an app whose menus run past ~900pt
on a 1600pt bar — B starts inside it and the « shows for that app. Nothing
crosses a band wider than the cap without starting inside it, so this is
not a limit of two items; Barn logs it and stops retrying.

**Reveal.** Both lines go narrow; siblings yield; the block appears. As
before.

**Between the lines.** Only the user can put something there (⌘-drag). Barn
notices — an item whose slot overlaps the « or sits between A's and B's
logical positions — and reports it in the menu rather than fighting the
drag.

## Out of scope

- Switching the agent's overflow off. There is no preference or API for it;
  Barn makes it moot.
- Automatic un-collapse.
