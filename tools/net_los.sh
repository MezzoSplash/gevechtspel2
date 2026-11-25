#!/usr/bin/env bash
# Two-process network check for the LOS chain (#384): a dedicated server that charges every human
# with the LOS streak, plus the client half that flies at a bot and bashes twice.
#   tools/net_los.sh
# run_checks.sh does not run this one: the runner has no server of its own, and a check that needs
# one is not a gate.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -n "${GODOT:-}" ]]; then :
elif [[ -x "$HOME/.local/bin/godot" ]]; then GODOT="$HOME/.local/bin/godot"
elif command -v godot >/dev/null; then GODOT="$(command -v godot)"
else echo "Godot not found; set GODOT=..." >&2; exit 2; fi
PORT="${PORT:-7801}"
LOG="${TMPDIR:-/tmp}/net_los_server.log"
: > "$LOG"
"$GODOT" --headless --path "$ROOT" -- --server --port "$PORT" --map quay --mode ffa --bots 4 \
	--bot-difficulty easy --test-los --time 10 > "$LOG" 2>&1 &
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
timeout 420 "$GODOT" --headless --path "$ROOT" res://tools/check_net_los.tscn
RC=$?
if [[ $RC -ne 0 ]]; then echo "server log: $LOG" >&2; fi
exit $RC
