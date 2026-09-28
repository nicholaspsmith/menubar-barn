# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.3.1] - 2026-09-28

- `install.sh` now asks whether to turn on Start at Login (skipped when it is already on, or when there is no terminal to ask in) instead of turning it on unasked, then relaunches the app, quitting any running copy first so the new build takes over

## [1.3.0] - 2026-09-26

### Show and hide from the panel

- Each app's row in the panel now has its own tick: ticked means the icon is out on the menu bar, unticked means it lives in the barn. Click a ticked row to put it away; open an unticked row's menu and choose "Show on the Bar" to bring it back.
- An app that has no menu of its own gets "Show on the Bar" and "Open <name>".
- Nothing in the panel is greyed out any more; every row can be clicked.
- "Visible Icons" is gone from the settings menu; the ticks replace it.

### Fixed

- The tick is its own click target, so it no longer fights the row.
- The system « stays down reliably: Barn checks the actual arrangement of the bar, not just the widths.

## [1.2.0] - 2026-09-23

- feat: the menu shows the version it was built from
- fix: the footer's click reaches the row, and the settings pop waits for the panel to close
- feat: the panel's footer opens the settings menu

## [1.1.0] - 2026-09-23

- chore: 1.1, and the README shows the new panel
- feat: the panel lists every app, orderable; warnings fix themselves; the line fits wide displays
- verify: merge the agent's windows, and check the handle is on the bar
- feat: re-settle when the handle has gone off the bar
- fix: read every one of the agent's windows, not just the first
- chore: drop stray vim swap file and ignore *.swp
- LICENSE: name the copyright holder above the MPL text
- License: Mozilla Public License 2.0
- feat: two lines, no system «, and collapse-on-overflow on macOS 27
- fix: hiding works again on macOS 27's hosted menu bar
- docs: document the --login flag
- feat: --login on|off|status, and register Start at Login on install
- fix: Control Center is not offered in Visible Icons
- fix: the hidden list is re-read once the bar settles after a hide
- feat: Visible Icons — a tick means the icon is on the bar
- fix: the menu probe is read-only and runs once per app, not every poll (AXCancel on unopened menus stole focus every 5s)
- fix: the panel never touches Accessibility while it is being built
- fix: the line only changes its width when it actually changes (a redundant set cancelled the open panel)
- fix: the panel is the item's attached menu, so a quick click keeps it open and a held click selects on release
- fix: the barn shuts its doors when the panel closes, via popUp's completion
- fix: ship Barn.icns (the bundle folder vanished with the old icon)
- feat: Curtain is now Barn
- docs: Apollo Monitor described without the vendor name
- feat: the barn's doors open while its menu is up
- docs: drop the Ice migration section; Ice stays only as the counter-example
- docs: the character menu-bar icon, rendered from code, and what its states mean
- feat: barn handle on its own 26x22 canvas, bigger than the chevron
- feat: the barn fills the bar's full 22pt
- feat: the barn is barn red
- feat: barn icon for the handle, with a menu option to switch back to the chevron
- fix: judge 'still open' by the on-screen window list, not the AX tree
- feat: open a hidden app that only answers a real click by revealing and clicking
- fix: a restore must land right of the line; report every failed start
- fix: make restores reliable on a full bar
- fix: sweep the accessibility API concurrently and skip bar-less processes
- fix: refuse to show an icon the bar has no room for; offer undo if the chevron strands anyway
- docs: mention the Menubarn widget library
- docs: why a standalone app beats a SwiftBar plugin
- docs: add the Menubarn mascot to the README
- Advertise the menu-bar suite
- Add a script that reports the menu bar and names anything stranded
- Rewrite the README to lead with what it does
- Give Curtain an app icon
- Restore a hidden icon to the slot it came from
- Add README and install script
- Put the pointer back after a drag, and stop padding the shuffle
- Make an app's own row clickable, and never leave one unreachable
- Show each row's keyboard shortcut in the panel
- Offer Manage Icons from the panel
- Drop the reveal row from the panel
- fix: menu-less apps open themselves, and defer presses until our menu closes
- feat: Manage Icons checklist to move icons across the line
- feat: panel listing hidden apps with their live menus
- fix: restore the yielded icons instantly, and drop the toggle menu row
- feat: click to toggle, right-click menu, and peek
- feat: stranded-icon watchdog, and make revealing self-reversing
- feat: two-item curtain - invisible line plus visible handle
- feat: curtain item that hides a block by its own width
- feat: self-describing yield session with its own deadline
- feat: menu bar geometry with an empirical notch dead zone
- spike: verify synthesized cmd-drag moves a status item
- docs: plan the curtain implementation
- docs: spec the menu-bar curtain (Ice replacement)
