#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
if [[ ! -x "$GODOT" ]]; then
	echo "Godot not found at $GODOT" >&2
	echo "Install Godot 4.7.x or set GODOT=..." >&2
	exit 1
fi
exec "$GODOT" --path "$ROOT" "$@"
