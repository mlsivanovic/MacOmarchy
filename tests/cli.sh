#!/bin/sh
# CLI behaviour: sparse writes, validation and reset. Uses a throwaway config dir.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cli="$root/bin/macomarchy"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

[ "$("$cli" --config-dir "$tmp" config get tiler.gap)" = "4" ] || fail "default gap"
[ "$("$cli" --config-dir "$tmp" config get desktops.maxNumber)" = "9" ] || fail "default maxNumber"

"$cli" --config-dir "$tmp" config set tiler.gap 6 >/dev/null
[ "$("$cli" --config-dir "$tmp" config get tiler.gap)" = "6" ] || fail "stored gap"
[ "$("$cli" --config-dir "$tmp" config get tiler.margin)" = "4" ] || fail "default margin survives"

python3 - "$tmp/settings.json" <<'PY' || fail "sparse file"
import json, sys
data = json.load(open(sys.argv[1]))
assert data == {"tiler": {"gap": 6}}, data
PY

before=$(cat "$tmp/settings.json")
if "$cli" --config-dir "$tmp" config set tiler.gap 999 >/dev/null 2>&1; then fail "range accepted"; fi
if "$cli" --config-dir "$tmp" config set tiler.unknown 1 >/dev/null 2>&1; then fail "unknown accepted"; fi
[ "$(cat "$tmp/settings.json")" = "$before" ] || fail "rejected write touched the file"

"$cli" --config-dir "$tmp" config diff | grep -q "tiler.gap: 4 -> 6" || fail "diff output"
"$cli" --config-dir "$tmp" config validate | grep -q "1 override" || fail "validate output"

"$cli" --config-dir "$tmp" config unset tiler.gap >/dev/null
[ "$("$cli" --config-dir "$tmp" config get tiler.gap)" = "4" ] || fail "unset restores default"
"$cli" --config-dir "$tmp" config diff | grep -q "No overrides" || fail "empty diff"

"$cli" --config-dir "$tmp" config set focus.delay 0.2 >/dev/null
[ "$("$cli" --config-dir "$tmp" config get shortcuts.layout_next)" = "ctrl+alt+l" ] || fail "default shortcut"
"$cli" --config-dir "$tmp" config set shortcuts.layout_next ctrl+alt+j >/dev/null
[ "$("$cli" --config-dir "$tmp" config get shortcuts.layout_next)" = "ctrl+alt+j" ] || fail "stored shortcut"
if "$cli" --config-dir "$tmp" config set shortcuts.layout_tall ctrl+alt+j >/dev/null 2>&1; then fail "shortcut conflict accepted"; fi
if "$cli" --config-dir "$tmp" config set shortcuts.layout_tall ctrl+alt++ >/dev/null 2>&1; then fail "malformed shortcut accepted"; fi
"$cli" --config-dir "$tmp" config set shortcuts.clipboard_history none >/dev/null
[ "$("$cli" --config-dir "$tmp" config get shortcuts.clipboard_history)" = "none" ] || fail "disabled shortcut"
"$cli" --config-dir "$tmp" config unset shortcuts.layout_next >/dev/null
"$cli" --config-dir "$tmp" config unset shortcuts.clipboard_history >/dev/null
if "$cli" --config-dir "$tmp" config reset >/dev/null 2>&1; then fail "reset without --yes"; fi
"$cli" --config-dir "$tmp" config reset --yes >/dev/null
[ "$("$cli" --config-dir "$tmp" config get focus.delay)" = "0.1" ] || fail "reset defaults"

custom="$tmp/custom-settings.json"
MACOMARCHY_SETTINGS="$custom" "$cli" config set tiler.gap 5 >/dev/null
[ "$("$cli" --config-dir "$tmp" config get tiler.gap)" = "4" ] || fail "config-dir should win over env"
MACOMARCHY_SETTINGS="$custom" "$cli" config get tiler.gap | grep -q 5 || fail "env settings path"

echo "PASS: settings CLI sparse writes and validation"
