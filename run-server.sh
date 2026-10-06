#!/usr/bin/env bash
# Usage: ./run-server.sh [port] [--map townhouses|foundry|rooftops] [--mode tdm|ffa] [--kills N] [--time MIN] [--bots N]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-7777}"
exec "$ROOT/run.sh" --headless -- --server --port "$PORT" "${@:2}"
