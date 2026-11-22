#!/usr/bin/env bash
# Bot parity for refactors (#317): traces a seeded 60 s TDM bot fight (tools/probe_bot_trace) with Hard
# bots on the four maps whose trace is deterministic, into OUT_DIR. Run it on main and on the branch:
#   tools/bot_parity.sh /tmp/main && (git switch branch) && tools/bot_parity.sh /tmp/branch
#   diff -r /tmp/main /tmp/branch && echo IDENTICAL
# Left out because they are not deterministic run to run: Skyline (one of two traces, a race while it
# loads), FFA (main.gd spaces FFA spawns by wall-clock time) and Easy/Medium (BotBrain's hearing reads
# Time.get_ticks_msec). Godot runs with its own XDG_DATA_HOME: the menu saves every match choice to
# settings.cfg, so without it the probe would overwrite your own menu settings (and read them).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: tools/bot_parity.sh OUT_DIR}"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT
export XDG_DATA_HOME="$DATA"
mkdir -p "$OUT"
cd "$ROOT"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
for map in quay foundry townhouses rooftops; do
	timeout 300 "$GODOT" --headless --fixed-fps 60 --path . res://tools/probe_bot_trace.tscn -- \
		"$OUT/$map.txt" "$map" tdm 3600 hard 2>&1 | grep -E "SCRIPT ERROR" || true
done
md5sum "$OUT"/*.txt
