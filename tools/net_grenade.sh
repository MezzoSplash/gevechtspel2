#!/usr/bin/env bash
# Two-process network check: a dedicated server on port 7799 plus the client half that throws frags.
#   tools/net_grenade.sh
# run_checks.sh does not run this one: the runner has no server of its own, and a check that needs
# one is not a gate.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -n "${GODOT:-}" ]]; then :
elif [[ -x "$HOME/.local/bin/godot" ]]; then GODOT="$HOME/.local/bin/godot"
elif command -v godot >/dev/null; then GODOT="$(command -v godot)"
else echo "Godot not found; set GODOT=..." >&2; exit 2; fi
LOG="${TMPDIR:-/tmp}/net_grenade_server.log"
"$GODOT" --headless --path "$ROOT" -- --server --port 7799 --map quay --mode ffa --bots 0 > "$LOG" 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null' EXIT
for _i in $(seq 1 60); do
	grep -q "Server started on port" "$LOG" && break
	sleep 0.5
done
if ! grep -q "Server started on port" "$LOG"; then
	echo "server did not start; see $LOG" >&2
	exit 2
fi
"$GODOT" --headless --path "$ROOT" res://tools/check_net_grenade.tscn
