#!/usr/bin/env bash
# Two-process network check for Overdrive (#388): a dedicated server that charges every human with
# Overdrive, plus the client half that sprints, looks at the glow and waits for the end.
#   tools/net_overdrive.sh
# run_checks.sh does not run this one: the runner has no server of its own, and a check that needs
# one is not a gate.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -n "${GODOT:-}" ]]; then :
elif [[ -x "$HOME/.local/bin/godot" ]]; then GODOT="$HOME/.local/bin/godot"
elif command -v godot >/dev/null; then GODOT="$(command -v godot)"
else echo "Godot not found; set GODOT=..." >&2; exit 2; fi
PORT="${PORT:-7802}"
LOG="${TMPDIR:-/tmp}/net_overdrive_server.log"
: > "$LOG"
"$GODOT" --headless --path "$ROOT" -- --server --port "$PORT" --map quay --mode ffa --bots 2 \
	--bot-difficulty easy --test-overdrive --time 10 > "$LOG" 2>&1 &
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
timeout 420 "$GODOT" --headless --path "$ROOT" res://tools/check_net_overdrive.tscn
RC=$?
if [[ $RC -ne 0 ]]; then echo "server log: $LOG" >&2; fi
exit $RC
