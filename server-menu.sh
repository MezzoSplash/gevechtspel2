#!/usr/bin/env bash
# Interactive menu to start a Gevechtspel dedicated server.
#   ./server-menu.sh            guided setup (whiptail/dialog if installed, plain prompts otherwise)
#   ./server-menu.sh --defaults start straight away with saved defaults
# Binary: $GEVECHTSPEL_BIN, else most recently modified gevechtspel-*-linux-x86_64 next to this script
# (or in Exportbuilds/), else run from source via run.sh (needs Godot).
# Defaults are saved in ~/.config/gevechtspel/server.conf
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/gevechtspel/server.conf"
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/gevechtspel-server.service"
MAPS=(townhouses foundry rooftops quay skyline)   # scripts/maps.gd ORDER
# Ranges from shared/game.gd
KILLS_MIN=5; KILLS_MAX=50; TIME_MIN=1; TIME_MAX=20; BOTS_MAX=16

MAP=townhouses MODE=tdm BOTS=8 KILLS=25 TIME=10 PORT=7777 BIN="${GEVECHTSPEL_BIN:-}"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF"
BIN="${GEVECHTSPEL_BIN:-$BIN}"

UI=plain
if [[ -t 0 && -z "${PLAIN:-}" ]]; then
	if command -v whiptail >/dev/null; then UI=whiptail
	elif command -v dialog >/dev/null; then UI=dialog; fi
fi

die() { echo "Error: $*" >&2; exit 1; }
in_range() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= $2 && $1 <= $3 )); }

find_bin() {
	[[ -n "$BIN" && -x "$BIN" ]] && return
	local c
	# shellcheck disable=SC2012
	c=$(ls -1t "$DIR"/gevechtspel-*-linux-x86_64 "$DIR"/Exportbuilds/gevechtspel-*-linux-x86_64 2>/dev/null | head -n1 || true)
	BIN="$c"
}

# ask_menu "title" default item...   -> echoes choice
ask_menu() {
	local title="$1" def="$2"; shift 2
	if [[ $UI != plain ]]; then
		local args=() i
		for i in "$@"; do args+=("$i" ""); done
		$UI --title "Gevechtspel server" --default-item "$def" --menu "$title" 18 60 8 "${args[@]}" 3>&1 1>&2 2>&3 || exit 1
		return
	fi
	echo "$title (default: $def)" >&2
	local n=1 i
	for i in "$@"; do echo "  $n) $i" >&2; n=$((n+1)); done
	local r; read -r -p "> " r || exit 1
	if [[ -z "$r" ]]; then echo "$def"
	elif [[ "$r" =~ ^[0-9]+$ ]] && (( r >= 1 && r <= $# )); then echo "${!r}"
	else for i in "$@"; do [[ "$i" == "$r" ]] && { echo "$i"; return; }; done; echo "$def"; fi
}

# ask_num "question" default min max
ask_num() {
	local q="$1" def="$2" lo="$3" hi="$4" r
	while true; do
		if [[ $UI != plain ]]; then
			r=$($UI --title "Gevechtspel server" --inputbox "$q ($lo-$hi)" 9 60 "$def" 3>&1 1>&2 2>&3) || exit 1
		else
			read -r -p "$q ($lo-$hi) [$def]: " r || exit 1
		fi
		r="${r:-$def}"
		in_range "$r" "$lo" "$hi" && { echo "$r"; return; }
		echo "Please enter a number from $lo to $hi." >&2
	done
}

ask_yes() {
	if [[ $UI != plain ]]; then $UI --title "Gevechtspel server" --yesno "$1" 20 74; return; fi
	local r; read -r -p "$1 [y/N]: " r || return 1; [[ "$r" =~ ^[yYjJ] ]]
}

build_cmd() {
	ARGS=(--server --port "$PORT" --map "$MAP" --mode "$MODE" --bots "$BOTS" --kills "$KILLS" --time "$TIME")
	if [[ -n "$BIN" ]]; then CMD=("$BIN" --headless -- "${ARGS[@]}")
	else CMD=("$DIR/run.sh" --headless -- "${ARGS[@]}"); fi
}

validate() {
	[[ " ${MAPS[*]} " == *" $MAP "* ]] || die "unknown map '$MAP'"
	[[ $MODE == tdm || $MODE == ffa || $MODE == style-tdm || $MODE == style-ffa ]] || die "mode must be tdm, ffa, style-tdm or style-ffa"
	in_range "$BOTS" 0 "$BOTS_MAX" || die "bots must be 0-$BOTS_MAX"
	in_range "$KILLS" "$KILLS_MIN" "$KILLS_MAX" || die "kills must be $KILLS_MIN-$KILLS_MAX"
	in_range "$TIME" "$TIME_MIN" "$TIME_MAX" || die "time must be $TIME_MIN-$TIME_MAX"
	in_range "$PORT" 1 65534 || die "port must be 1-65534"
}

save_defaults() {
	mkdir -p "$(dirname "$CONF")"
	printf 'MAP=%q\nMODE=%q\nBOTS=%q\nKILLS=%q\nTIME=%q\nPORT=%q\nBIN=%q\n' \
		"$MAP" "$MODE" "$BOTS" "$KILLS" "$TIME" "$PORT" "$BIN" > "$CONF"
	echo "Saved defaults to $CONF"
}

write_service() {
	mkdir -p "$(dirname "$UNIT")"
	if [[ -f "$UNIT" ]]; then
		cp -p "$UNIT" "$UNIT.bak-$(date +%Y%m%d%H%M%S)"
		echo "Backed up existing service."
	fi
	local exec_line; exec_line=$(printf '%q ' "${CMD[@]}")
	cat > "$UNIT" <<UNITEOF
[Unit]
Description=Gevechtspel dedicated server
After=network-online.target

[Service]
WorkingDirectory=$(dirname "${CMD[0]}")
ExecStart=${exec_line% }
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNITEOF
	systemctl --user daemon-reload
	systemctl --user restart gevechtspel-server
	systemctl --user --no-pager status gevechtspel-server | head -n 5 || true
}

find_bin
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0; fi
if [[ "${1:-}" != "--defaults" ]]; then
	MAP=$(ask_menu "Map" "$MAP" "${MAPS[@]}")
	MODE=$(ask_menu "Mode (tdm = Team Deathmatch, ffa = Free for all, style-* = most style points wins)" "$MODE" tdm ffa style-tdm style-ffa)
	BOTS=$(ask_num "Number of bots" "$BOTS" 0 "$BOTS_MAX")
	if [[ $MODE == style-* ]]; then
		KILLS=$(ask_num "Style per minute in hundreds (25 = 2500/min, x the time limit)" "$KILLS" "$KILLS_MIN" "$KILLS_MAX")
	else
		KILLS=$(ask_num "Kill limit" "$KILLS" "$KILLS_MIN" "$KILLS_MAX")
	fi
	TIME=$(ask_num "Time limit in minutes" "$TIME" "$TIME_MIN" "$TIME_MAX")
	PORT=$(ask_num "UDP game port (status query uses port+1)" "$PORT" 1024 65534)
fi
validate
build_cmd
SUMMARY="Map:    $MAP
Mode:   $MODE
Bots:   $BOTS
Limit:  $KILLS$([[ $MODE == style-* ]] && echo " (x100 style points per minute)" || echo " kills")
Time:   $TIME min
Ports:  $PORT/udp (game), $((PORT+1))/udp (server list status)

Command:
$(printf '%q ' "${CMD[@]}")"
[[ -z "$BIN" ]] && SUMMARY+=$'\n\n(no exported binary found, running from source)'

if [[ "${1:-}" == "--defaults" ]]; then echo "$SUMMARY"; exec "${CMD[@]}"; fi
[[ $UI == plain ]] && printf '\n%s\n\n' "$SUMMARY"
ask_yes "$SUMMARY

Continue?" || { echo "Cancelled."; exit 0; }
ask_yes "Save these choices as defaults?" && save_defaults
if command -v systemctl >/dev/null && ask_yes "Install as systemd user service (gevechtspel-server) and restart it? An existing service file is backed up first. Choose No to run it here in this terminal."; then
	write_service
	exit 0
fi
exec "${CMD[@]}"
