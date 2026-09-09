#!/usr/bin/env bash
# Capture every "NSStatusItem Preferred Position" value on this machine and emit
# a runnable restore script.
#
# Run this BEFORE quitting Ice, rearranging icons, or letting Barn drag
# anything. macOS stores each status item's position in the OWNING app's
# preferences, so a rearrangement is spread across dozens of domains and is
# tedious to undo by hand; this makes undo a single command.
#
# Usage: scripts/snapshot-positions.sh [output-path]
#        (default output: ./restore-positions.sh, which is gitignored)
set -euo pipefail

OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/restore-positions.sh}"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
    echo "#!/usr/bin/env bash"
    echo "# Restore menu-bar item positions captured $STAMP."
    echo "# Positions are read when an app creates its status item, so each"
    echo "# affected app must be relaunched (or you log out and back in) for"
    echo "# these to take effect."
    echo "set -euo pipefail"
    echo
} > "$OUT"

count=0
for plist in "$HOME"/Library/Preferences/*.plist; do
    domain="${plist%.plist}"
    # defaults read fails on domains it cannot parse; skip those quietly.
    values="$(defaults read "$domain" 2>/dev/null | grep 'NSStatusItem Preferred Position' || true)"
    [ -n "$values" ] || continue

    name="$(basename "$domain")"
    while IFS= read -r line; do
        # Lines look like:  "NSStatusItem Preferred Position Item-0" = 566;
        #               or: "NSStatusItem Preferred Position Clock" = "73.5";
        key="$(printf '%s' "$line" | sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p')"
        val="$(printf '%s' "$line" | sed -n 's/.*=[[:space:]]*"\{0,1\}\([^";]*\)"\{0,1\};.*/\1/p')"
        [ -n "$key" ] && [ -n "$val" ] || continue
        printf 'defaults write "%s" "%s" -float %s\n' "$name" "$key" "$val" >> "$OUT"
        count=$((count + 1))
    done <<< "$values"
done

{
    echo
    echo 'echo "Restored '"$count"' status item positions. Relaunch the affected apps."'
} >> "$OUT"

chmod +x "$OUT"
echo "Captured $count status item positions -> $OUT"
