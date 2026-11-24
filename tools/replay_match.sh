#!/usr/bin/env bash
# Play the seeded replay (#250) the only way it is reproducible: a fresh user:// and a fixed 60 fps.
# Your own saved menu choices (bot count, difficulty, map) live in user://settings.cfg and change the
# match, so a plain `godot ... replay_match.tscn` on a dev machine fails against the baseline.
# Usage: tools/replay_match.sh [map|all] [--update-baseline] [seed] [ticks]   (env: GODOT)
# Default: all five maps. Exit 1 when any map is outside the tolerance or logs a script error.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${GODOT:-}" ]]; then :
elif command -v godot >/dev/null; then GODOT="$(command -v godot)"
elif [[ -x "$HOME/.local/bin/godot" ]]; then GODOT="$HOME/.local/bin/godot"
else echo "Godot not found; set GODOT=..." >&2; exit 2; fi
MAPS=(quay foundry townhouses rooftops skyline)
if [[ $# -gt 0 && " ${MAPS[*]} " == *" $1 "* ]]; then MAPS=("$1"); shift
elif [[ "${1:-}" == "all" ]]; then shift; fi
fail=0
for map in "${MAPS[@]}"; do
	data="$(mktemp -d)"
	XDG_DATA_HOME="$data" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" res://tools/replay_match.tscn -- "$map" "$@" || fail=1
	rm -rf "$data"
done
exit $fail
