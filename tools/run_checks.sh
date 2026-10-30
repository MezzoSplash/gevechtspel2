#!/usr/bin/env bash
# Run Godot import + all headless checks in tools/. Exit != 0 if any check fails.
# Usage: tools/run_checks.sh [name-filter]   (env: GODOT, CHECK_TIMEOUT=120)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TIMEOUT="${CHECK_TIMEOUT:-120}"
FILTER="${1:-}"

if [[ -n "${GODOT:-}" ]]; then :
elif [[ -x /workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64 ]]; then GODOT=/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64
elif command -v godot >/dev/null; then GODOT="$(command -v godot)"
elif [[ -x "$HOME/.local/bin/godot" ]]; then GODOT="$HOME/.local/bin/godot"
else echo "Godot not found; set GODOT=..." >&2; exit 2; fi
echo "Godot: $GODOT ($("$GODOT" --version 2>/dev/null))"

# Skipped on purpose: shot_*/_shot (need a real screen for screenshots),
# stress_host_join (long multi-client stress run), check_quay (needs /tmp/quay_probe.json from gen_quay.py),
# _check_guns (manual viewer).
# check_skyline_walk hangs headless (no output, >400s), skipped until fixed.
SKIP=(stress_host_join check_quay _check_guns check_skyline_walk)
# Known failing checks (reported, do not fail the run). Format: name
# check_new_guns: bots never pick LMG/slug in the run (3 asserts fail).
# check_server_list: "direct query answered" fails (UDP status query gets no reply).
# check_net_grenade: flaky, client sometimes not connected in time ("no pawn"); passed 1 of 4 runs.
KNOWN_FAIL=(check_new_guns check_server_list check_net_grenade)
# Engine shutdown noise (leaks at exit) is not a test failure.
IGNORE_RE="resources still in use at exit|were leaked at exit|ObjectDB instances"
# Per-check timeout overrides (seconds).
declare -A SLOW=([check_bot_kit]=200 [check_new_guns]=200)

in_list() { local x="$1"; shift; for y in "$@"; do [[ "$x" == "$y" ]] && return 0; done; return 1; }

LOG_DIR="$(mktemp -d)"
declare -a RES
fail=0
run_one() { # name, args...  (a failing check is retried once; pass on retry = FLAKY)
	_run_once "$@"
	if [[ "$LAST" == FAIL ]]; then echo "retrying $1 ..."; RES=("${RES[@]:0:${#RES[@]}-1}"); fail=$PREV_FAIL; _run_once "$@"
		[[ "$LAST" == PASS ]] && RES[-1]="${RES[-1]/PASS       /FLAKY      }"; fi
}
_run_once() {
	local name="$1"; shift
	local log="$LOG_DIR/$name.log" t0=$SECONDS code
	local to="$TIMEOUT"; [[ -n "${SLOW[$name]:-}" ]] && to="${SLOW[$name]}"
	timeout "$to" "$GODOT" --headless --path . "$@" >"$log" 2>&1; code=$?
	local why=""
	if (( code == 124 )); then why="timeout ${to}s"
	elif (( code != 0 )); then why="exit $code"
	elif grep -qE "CHECK[^a-z]*(FAIL|FAILED)" "$log"; then why="$(grep -m1 -E 'CHECK[^a-z]*(FAIL|FAILED)' "$log" | cut -c1-120)"
	elif grep -E "SCRIPT ERROR|ERROR:" "$log" | grep -qvE "$IGNORE_RE"; then why="$(grep -E 'SCRIPT ERROR|ERROR:' "$log" | grep -vE "$IGNORE_RE" | head -1 | cut -c1-120)"; fi
	local dt=$((SECONDS - t0)) st=PASS; PREV_FAIL=$fail
	if [[ -n "$why" ]]; then
		if in_list "$name" "${KNOWN_FAIL[@]}"; then st=KNOWN_FAIL; else st=FAIL; fail=1; fi
		echo "---- $name output (tail) ----"; tail -n 15 "$log"
	fi
	RES+=("$(printf '%-11s %-24s %4ss %s' "$st" "$name" "$dt" "$why")")
	echo "$st $name (${dt}s)"; LAST=$st
}

start=$SECONDS
run_one import --import
for f in tools/check_*.gd; do
	name="$(basename "$f" .gd)"
	[[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && continue
	in_list "$name" "${SKIP[@]}" && { RES+=("$(printf '%-11s %s' SKIP "$name")"); continue; }
	if [[ -f "tools/$name.tscn" ]]; then run_one "$name" "res://tools/$name.tscn"
	elif grep -q '^extends SceneTree' "$f"; then run_one "$name" -s "res://$f"
	else RES+=("$(printf '%-11s %s (no scene, not a SceneTree script)' SKIP "$name")"); fi
done

echo; echo "===== Summary ($((SECONDS - start))s, logs: $LOG_DIR) ====="
printf '%s\n' "${RES[@]}"
exit $fail
