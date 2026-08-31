#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-7777}"
exec "$ROOT/run.sh" --headless -- --server --port "$PORT"
