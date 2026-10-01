#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Build Barn.app and symlink it into ~/Applications (rebuilds propagate;
# SMAppService accepts a symlink there for Start-at-Login).
set -euo pipefail

# Menumon release rule — every push is a release. Arm the pre-push hook in
# every Menumon repo cloned beside this one (local git config, so a fresh
# clone has none until this runs). StatusItemKit README, "Releases".
RELEASE_KIT="$(cd "$(dirname "$0")/.." && pwd)/StatusItemKit/scripts/release/adopt.sh"
if [ -x "$RELEASE_KIT" ]; then
    "$RELEASE_KIT" --hooks-only || echo "Release hook: adopt.sh failed" >&2
else
    echo "Release hook: StatusItemKit not found beside this repo — clone it and re-run" >&2
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Barn.app"

"$SRC_DIR/scripts/build-app.sh"

mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

# Ask to turn on Start at Login. SMAppService can only register the calling
# process's own bundle, so this runs the installed binary's headless --login.
APP="$HOME/Applications/$APP_NAME"
BIN="$APP/Contents/MacOS/Barn"
PROC="${APP##*/}/Contents/MacOS/Barn"   # matches the symlink-resolved path too
if [ "$("$BIN" --login status 2>/dev/null)" = "on" ]; then
    echo "Start at Login: already on"
elif [ -t 0 ]; then
    read -r -p "Start Barn at login? [Y/n] " answer
    case "$answer" in
        [nN]*) echo "Start at Login: left off (turn it on from the menu)" ;;
        *) if "$BIN" --login on >/dev/null; then
               echo "Start at Login: on"
           else
               echo "Start at Login: could not register (turn it on from the menu)" >&2
           fi ;;
    esac
else
    echo "Start at Login: off (not asked: no terminal). Turn it on from the menu, or run"
    echo "    \"$BIN\" --login on"
fi

# `open` on a running app only activates it, so quit the old build first or the
# new one never launches. Wait for it to go so both don't briefly sit in the bar.
if pgrep -f "$PROC" >/dev/null; then
    osascript -e "tell application id \"$(defaults read "$APP/Contents/Info" CFBundleIdentifier)\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$PROC" >/dev/null || break; sleep 0.5; done
    pkill -f "$PROC" 2>/dev/null || true
    sleep 1
fi
/usr/bin/open "$APP"

cat <<'EOF'

Barn is now running in the menu bar.

First-run setup
  1. Grant Accessibility when prompted (System Settings ▸ Privacy & Security ▸
     Accessibility). It is needed to read where every icon sits, to read hidden
     apps' menus, and to move an icon across the line. Until granted, hiding
     still works; the menu shows "⚠ Grant Accessibility…".
  2. Drag the chevron (⌘-drag) so everything you want hidden sits to its LEFT.
     Or left-click it and untick whatever you would rather not see.
  3. Optional: menu ▸ Start at Login.

Using it
  Left click   every app, ticked while its icon is on the bar; the hidden
               ones each carry their own live menu
  Right click  panel order, reveal behaviour, Icon, Start at Login, Quit

If you also run Ice or Bartender, quit it first — two managers fighting over
the same icons will strand one. See "Migrating off Ice" in README.md.
EOF
