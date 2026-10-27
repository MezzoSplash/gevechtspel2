#!/usr/bin/env bash
# Run a headless dedicated server from source (needs Godot, see run.sh).
# Usage: ./run-server.sh [port] [--map townhouses|foundry|rooftops|quay|skyline] [--mode tdm|ffa|style-tdm|style-ffa]
#                        [--bots 0-16] [--bot-difficulty easy|medium|hard] [--kills 5-50] [--style total-style-points] [--time 1-20]
# Default port 7777. The server list status query uses port + 1 (UDP).
# For a guided setup (exported binary or source) use ./server-menu.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
fi
PORT=7777
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
	PORT="$1"
	shift
fi
exec "$ROOT/run.sh" --headless -- --server --port "$PORT" "$@"
