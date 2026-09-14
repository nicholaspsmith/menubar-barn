#!/usr/bin/env bash
# Build Barn.app and symlink it into ~/Applications (rebuilds propagate;
# SMAppService accepts a symlink there for Start-at-Login).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Barn.app"

"$SRC_DIR/scripts/build-app.sh"

mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

# Register Start at Login. Without this the app only runs until the next reboot,
# and a menu-bar app that quietly fails to come back is easy to miss for weeks.
# SMAppService can only register the calling process's own bundle, so this has
# to run the installed binary rather than call launchctl.
if "$HOME/Applications/$APP_NAME/Contents/MacOS/Barn" --login on >/dev/null; then
    echo "Start at Login: on"
else
    echo "Start at Login: could not register (turn it on from the menu)" >&2
fi

open "$HOME/Applications/$APP_NAME"

cat <<'EOF'

Barn is now running in the menu bar.

First-run setup
  1. Grant Accessibility when prompted (System Settings ▸ Privacy & Security ▸
     Accessibility). It is needed to read where every icon sits, to read hidden
     apps' menus, and to move an icon across the line. Until granted, hiding
     still works; the menu shows "⚠ Grant Accessibility…".
  2. Drag the chevron (⌘-drag) so everything you want hidden sits to its LEFT.
     Or use right-click ▸ Manage Icons and let it do the dragging.
  3. Optional: menu ▸ Start at Login.

Using it
  Left click   the hidden icons, each with its own live menu
  Right click  Manage Icons, reveal behaviour, Start at Login, Quit

If you also run Ice or Bartender, quit it first — two managers fighting over
the same icons will strand one. See "Migrating off Ice" in README.md.
EOF
