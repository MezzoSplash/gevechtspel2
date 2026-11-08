class_name GameState
extends Node
## Autoload `Game`. Shared weapon stats, server-authoritative hits, scores, and LAN RPCs.
## Clients never decide damage, deaths, or bot actions.
##
## Game is the shared state and the network layer: every @rpc lives here, on the same node path on every
## machine, so the protocol (NET_VERSION) never depends on how the logic is organised. Most functions
## below are thin entry points that forward to a static helper (#106):
##   shared/combat.gd        damage, shot resolution, kills, deaths, respawns, regen, tracers
##   shared/match_rules.gd   modes, score limits, win checks, round clock, per-round reset
##   shared/match_flow.gd    round start/freeze/end, intermission, late join, roster, pings, LINE strips
##   shared/match_audio.gd   menu music, round sting, tension music
##   shared/tricks.gd        trickshot detection and history
##   shared/combo_ledger.gd  combos and style awarding
##   shared/streaks.gd       UAV / RC-XD scorestreaks and the radar
##   shared/throwables.gd    frag grenades and throwing knives
##   shared/lobby.gd         names, participants, lobby roster, join notices, chat
##   shared/game_settings.gd settings file, window, resolution, render
##   shared/keybinds.gd      key and mouse bindings
## A helper takes the autoload as its first argument (`game: GameState`) and never declares RPCs.

signal hit_confirmed(killed: bool, headshot: bool)
signal local_player_ready(player: Player)
signal score_changed(peer_id: int, score: int, name: String)
signal round_ended(winner_peer_id: int, winner_name: String, scores: Dictionary)
## `tricks`: "" or the trickshot label for the feed tag ("360 NOSCOPE + AIRSHOT").
signal kill_feed(killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int, tricks: String)
## Every machine: a kill was a trickshot. `tricks` is Style.pack form; `total` the killer's style this round.
## #84: this machine's own combo changed. state: "build", "landed", "bailed".
signal combo_changed(points: int, multiplier: float, time_left: float, label: String, state: String, banked: int)
signal trick_scored(killer_peer_id: int, tricks: String, points: int, multiplier: float, total: int)
signal presence(player_name: String, joined: bool, team: int)
signal chat_message(player_name: String, team: int, text: String)
signal lobby_changed
signal match_starting
signal round_freeze_changed(frozen: bool)
signal intermission_started
## Fired when the saved profile name changes, so the menu fields stay in sync.
signal local_name_changed(n: String)
signal hud_settings_changed # crosshair, minimap, killfeed, colourblind palette

const DEFAULT_PORT := 7777
const SHOT_MASK := 1 | 2 | 4 # world | players | leftover dummy layer
const WIN_KILLS := 25
const TEAM_SIZE := 5 # shipped 5v5 size; live fill uses bot_count (default 9 bots + you)
const TEAM_A := 0
const TEAM_B := 1
const TEAM_NAMES := ["BLUE", "ORANGE"]
## Match modes. Team ids stay in FFA (bot fill/balancing), but nobody is a teammate: use is_enemy().
const MODE_TDM := 0
const MODE_FFA := 1
const MODE_STYLE_TDM := 2 # #82: same teams as TDM, but the team with the most style points wins
const MODE_STYLE_FFA := 3 # #82: FFA where the player with the most style points wins
const MODE_GUN_GAME := 4 # #148: FFA weapon ladder, see shared/gun_game.gd
const MODE_CTF := 5 # #160: Capture the Flag (teams), see shared/ctf.gd; only on maps with flag bases
const MODE_LAST := MODE_CTF
const MODE_IDS := ["tdm", "ffa", "style-tdm", "style-ffa", "gungame", "ctf"]
const MODE_NAMES := ["Team Deathmatch", "Free For All", "Style Team Deathmatch", "Style Free For All", "Gun Game", "Capture the Flag"]
## Menu chips: the same modes, short enough to read side by side. The tooltip carries the full name.
const MODE_SHORT_NAMES := ["TDM", "FFA", "Style TDM", "Style FFA", "Gun Game", "CTF"]
const MODE_HINTS := [
	"Team Deathmatch - Blue vs Orange, first team to the kill limit.",
	"Free For All - everyone against everyone, first player to the kill limit.",
	"Style Team Deathmatch - Blue vs Orange, the team with the most style points wins.",
	"Style Free For All - everyone against everyone, the most style points wins.",
	"Gun Game - work through the gun ladder; a knife kill sends the victim back one gun.",
	"Capture the Flag - steal the other team's flag and carry it home (maps with flag bases).",
]
## Style modes reuse kill_limit as a style RATE: STYLE_UNIT points per minute of round time, so the limit
## grows with the round (FFA default 25 → 2500/min → 25 000 in 10 min). Measured: one landed combo is
## ~1 000–6 000 (moves 30–120 each, up to ×6), bots alone make ~300–500/min; the old flat 2 000/3 000 ended
## a match on the first big combo.
const STYLE_UNIT := 100
const STYLE_TDM_LIMIT := 40 # 4 000 style per minute for a team
const STYLE_FFA_LIMIT := 25 # 2 500 style per minute for one player
const FFA_WIN_KILLS := 20
const KILLS_MIN := 5
const KILLS_MAX := 50
const TIME_MIN_MINUTES := 1
const TIME_MAX_MINUTES := 20
const BOT_COUNT_DEFAULT := 9
const BOT_COUNT_MAX := 16
## Split default: 9 bots over two teams, the player's side one shorter (5v5 with you on Blue).
const BOT_ALLIES_DEFAULT := 4
const BOT_ENEMIES_DEFAULT := 5
const MOUSE_SENS_MIN := 0.1
const MOUSE_SENS_MAX := 4.0
const ADS_SENS_MIN := 0.1
const ADS_SENS_MAX := 1.5
const WINDOW_WINDOWED := 0
const WINDOW_BORDERLESS := 1 # DisplayServer borderless fullscreen (the monitor's own resolution)
const WINDOW_FULLSCREEN := 2 # exclusive fullscreen; the chosen resolution is the mode
const FOV_MIN := 70.0
const FOV_MAX := 110.0
const FPS_CAP_MAX := 360
## Presets the video menu offers, plus the monitor's own size when that is not in this list.
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
	Vector2i(3840, 2160),
]
const ROUND_TIME := 600.0
const WARMUP_TIME := 5.0
const ROUND_END_TIME := 5.0
const INTERMISSION_TIME := 10.0
const FREEZE_TIME := 3.0
const NAME_MAX := 24
## Checked in the ENet auth step (main.gd). Bump with each release that changes RPCs or sync,
## when a new map id ships, and when map collision changes: each machine moves on its own mesh.
## Old clients get a clear "version mismatch" instead of a silent wrong map.
## 0.3.4 is the Quay rework (side lanes, offices, gantry, roof screens, new spawns).
## 0.3.6: RC-XD physics. rc_drive's yaw is now the aim, sync_rc_pose carries velocity, and the
## driver's prediction must match the server's handling. Blast knockback adds sync_knockback and
## sync_rc_kick. 0.3.5 and older cannot join.
## 0.3.7: the 3-kill streak is a 25 s UAV on the minimap, not the old 4 s radar.
## 0.3.6 and older cannot join.
const NET_VERSION := "0.5.12" # 0.5.12: Rooftops, Foundry and Townhouses geometry changed (skybridges, roof wallrun walls, plaza alleys) - a 0.5.11 client collides against different walls, so 0.5.11 peers are refused. 0.5.11: new Skyline geometry (bigger roofs, spine, surf entry, wallrun alley) - a 0.5.10 client collides against different roofs, so 0.5.10 peers are refused. 0.5.10: the reliable RPCs are split over ENet channels (1 gameplay, 2 cosmetic, 0 state) so one lost packet for the HUD no longer holds back a shot; a 0.5.7 peer must be refused. 0.5.8: LOS polish (los_recall; Style.LOS_LONG for a snap from 25 m+, checked in check_los); a 0.5.7 peer must be refused. 0.5.7: LOS pays off (a bash from the hands is lethal and a hit snaps the body to the hands: sync_los_end carries the snap position); a 0.5.6 peer must be refused. 0.5.6: LOS, the hands scorestreak (sync_los_spawn, sync_los_pose, sync_los_end, los_input, los_melee); a 0.5.5 peer must be refused. 0.5.5: the server checks the position a client claims and corrects it (#B1); a 0.5.4 peer must be refused. 0.5.3: physical UAV drone (sync_uav_spawn/end); 0.5.2: playtest balance: damage falloff (#147), MVP killcam without bots (#149), style killstreak factor (#151); pose sync unreliable at 30 Hz (high-ping desync); shot view time + server clock stamp (#105, lag compensation); combo "frozen" state (#89) + RCXD trick (#87): a 0.4.1 peer must be refused
const REGEN_SYNC := 0.25 # seconds between sync_regen batches
## Server-side shot checks. Lenient on purpose: LAN jitter must never eat a legit shot.
const FIRE_RATE_SLACK := 1.15 # shot credit refills 15% faster than the gun fires
const FIRE_ORIGIN_TOLERANCE := 4.0 # metres between the client's eye and our copy of it
const SPREAD_MAX := Player.SPREAD_SLIDE # slide spread; clients cannot ask for more (or less than standing)
const WEAPON_DEFS := {
	&"rifle": preload("res://data/weapons/rifle.tres"),
	&"pistol": preload("res://data/weapons/pistol.tres"),
	&"shotgun": preload("res://data/weapons/shotgun.tres"),
	&"sniper": preload("res://data/weapons/sniper.tres"),
	&"smg": preload("res://data/weapons/smg.tres"),
	&"revolver": preload("res://data/weapons/revolver.tres"),
	&"lmg": preload("res://data/weapons/lmg.tres"),
	&"slug": preload("res://data/weapons/slug.tres"),
}

var is_offline := true
var is_dedicated := false
var chat_open := false # T-chat: blocks move/look/fire until Enter/Esc
var pause_open := false
var in_lobby := false
var round_frozen := false # look OK, no walk/shoot; bots idle
var killcam_active := false # final killcam: no walk/look/shoot/damage; bots idle (Killcam.sync_lock)
var rc_view := false # this machine is looking out of an RC-XD; the pawn stays put and cannot shoot
var los_view := false # this machine is looking through LOS hands; the body keeps its line and cannot shoot
var final_kill: Dictionary = {} # match authority: last real kill of this round, replayed by the killcam
var flags: Array = [] # #160 CTF: [blue, orange] Objective dicts (authority decides, all mirror)
var ctf_caps: Array = [0, 0] # #160 CTF: captures per team this round
var gun_level: Dictionary = {} # #148 Gun Game: peer_id → 0-based ladder step (authority decides, all mirror)
var best_trick: Dictionary = {} # match authority: this round's highest-scoring trickshot (same keys + tags/pts/trick_id)
var _lag_history: Dictionary = {} # server: LagComp samples per player instance id
var _shot_rewind: Array = [] # server, while a client shot resolves: LagComp.offsets_for
var _server_clock_offset := 0 # client: server ms minus local ms at the last sync_pings (LagComp.view_ms)
var _shot_ctx: Dictionary = {} # match authority, while a shot resolves: {shooter, origin, scoped}
var _style_chain: Dictionary = {} # peer_id -> [trick kills in a row, time of the last one]
var _line_cd: Dictionary = {} # peer_id -> {strip name: seconds left}. Points only; the shove is local.
var _line_chain: Dictionary = {} # peer_id -> [last strip name, seconds left in the carry window]
var _line_pos: Dictionary = {} # peer_id -> last physics position (speed is the delta, not _obs_speed)
var _line_ms: Dictionary = {} # peer_id -> ticks_msec of that position: the start of the speed window
var _bursts: Dictionary = {} # peer_id -> {seq, t, victims}: the rifle burst (held trigger) in progress
var _shotgun_kill_t: Dictionary = {} # peer_id -> time of their last shotgun kill (DOUBLE)
var _hs_streak: Dictionary = {} # peer_id -> rifle headshot kills in a row (HEADSHOT STREAK)
var _mags: Dictionary = {} # peer_id -> {weapon_id: {seq, shots, kills}}: the magazine in use (HOSE, SIX SHOOTER)
var _knife_visuals: Dictionary = {} # net_id -> client copy of a flying knife
var _trick_seq := 0
var killcam: Killcam
var melee: Melee
var impacts: ImpactMarks
var loadouts: Loadouts
var radar_left := 0.0 # this machine: own team's radar time left (enemy markers on)
var radar_team := -1 # team whose radar is running here; its enemies get markers
var radar_peer := 0 # FFA: who activated the radar running here (only that machine gets markers)
var mode := MODE_TDM # server-owned; clients get it with sync_match_config
var map_id: StringName = Maps.DEFAULT
var map_kill_y := -INF # from the map root's metadata kill_y; pawns under it die (player.gd)
var mouse_sens := 1.0 # multiplier on Player.MOUSE_SENS (settings)
var ads_sens := 0.45 # extra multiplier while aiming down sights / scoped
var last_map: StringName = Maps.DEFAULT # menu's last pick (settings.cfg [match])
var last_mode := MODE_TDM
var last_kills := WIN_KILLS
var last_time_min := 10
var last_bots := BOT_COUNT_DEFAULT
## Menu: bots on your own side and bots on the other side (team modes). -1 = not chosen (FFA).
var last_bot_allies := BOT_ALLIES_DEFAULT
var last_bot_enemies := BOT_ENEMIES_DEFAULT
## #90 bot difficulty (server/offline only; bots run there). HARD is how bots played up to v0.4.1.
const BOT_EASY := 0
const BOT_MEDIUM := 1
const BOT_HARD := 2
const BOT_DIFFICULTY_IDS := ["easy", "medium", "hard"]
const BOT_DIFFICULTY_NAMES := ["Easy", "Medium", "Hard"]
## acquire: s before the first shot on a new target; wobble: × aim hand size; track: aim catch-up (1/s);
## pause: × pause between bursts; nade: × grenade cooldown; streak: s before using an earned streak.
const BOT_PROFILES := [
	{"acquire": 0.75, "wobble": 2.3, "track": 5.0, "pause": 1.9, "nade": 2.5, "streak": 6.0},
	{"acquire": 0.48, "wobble": 1.6, "track": 8.5, "pause": 1.4, "nade": 1.6, "streak": 3.0},
	{"acquire": 0.28, "wobble": 1.0, "track": 14.0, "pause": 1.0, "nade": 1.0, "streak": 1.2},
]
var bot_difficulty := BOT_MEDIUM
var last_bot_difficulty := BOT_MEDIUM


func bot_profile() -> Dictionary:
	return BOT_PROFILES[clampi(bot_difficulty, BOT_EASY, BOT_HARD)]


## "easy" / "e" / "0" → BOT_EASY ... Unknown → -1.
static func parse_bot_difficulty(raw: String) -> int:
	var s := raw.strip_edges().to_lower()
	if s in ["easy", "e", "0"]:
		return BOT_EASY
	if s in ["medium", "normal", "m", "1"]:
		return BOT_MEDIUM
	if s in ["hard", "h", "2"]:
		return BOT_HARD
	return -1
var kill_limit := WIN_KILLS # this match: TDM team total, FFA personal
var round_time := ROUND_TIME # this match, seconds
var bot_count := BOT_COUNT_DEFAULT # this match: how many bot pawns to keep (FFA: the only number)
var bot_allies := -1 # team modes: bots on bot_team_base's side (-1 = fill by bot_count, balanced)
var bot_enemies := -1 # team modes: bots on the other side
var bot_team_base := TEAM_A # whose side "allies" are: the team the match owner starts on
## main.gd: Callable(Player) -> Transform3D. Every respawn asks it (FFA: spot farthest from enemies).
var spawn_picker: Callable
## main.gd: Callable(map_id, mode) -> void. Clients load the server's map before their pawn spawns.
var match_config_handler: Callable
var lobby: Dictionary = {} # peer_id → {name, team}
var master_vol := 1.0
var sfx_vol := 1.0
## Enemy shots, steps, slides, landings, reloads (#59). Routed through SFX, so Effects scales it too.
## Above 1.0 is a boost: the default makes enemies a bit louder than before.
const ENEMIES_VOL_DEFAULT := 1.4
const ENEMIES_VOL_MAX := 2.0
var enemies_vol := ENEMIES_VOL_DEFAULT
var player_name := "Player" # this launch. --name replaces it and must not be written back.
const RECENT_SERVERS_MAX := 5
var recent_servers: PackedStringArray = [] # "ip:port", newest first (settings.cfg [net] recent)
## Join tab: last server picked or joined (prefilled next time), and the saved server list
## ("label|host:port"). Default: the official EliteDesk server on its public address.
const DEFAULT_FAVORITES := ["EliteDesk|77.169.214.14:7777"]
const QUERY_PORT_OFFSET := 1 # server info answers on UDP game port + 1 (7778 for 7777)
var last_server := ""
var favorite_servers: PackedStringArray = PackedStringArray(DEFAULT_FAVORITES)
var server_query: ServerQuery
var freeze_grade: FreezeGrade
## Speed lines overlay (Game.speed_fx). One instance for the whole process; the local pawn drives
## the intensity. Created in _ready like freeze_grade, hidden until someone is moving fast.
var speed_lines: SpeedLines
var hosted_port := 0 # set while this process is a server; ServerQuery answers on hosted_port + 1
var profile_name := "Player" # the name settings.cfg keeps across launches
var window_mode := WINDOW_WINDOWED
var window_size := Vector2i(1600, 900) # project.godot's window override; the first-run default
var vsync := true
var max_fps := 0 # 0 = no Engine cap. VSync, when on, still follows the monitor.
var fov := 90.0 # hip fire. Weapon ADS fov stays absolute so a scope does not scale with this.
var render_scale := 1.0 # 3D buffer only (Viewport.scaling_3d_scale). HUD stays at the window size.
var msaa := 2 # Viewport.MSAA: 0 off, 1 = 2x, 2 = 4x, 3 = 8x. Matches project.godot msaa_3d=2 (4x).
## Performance overlay in the HUD: 0 off, 1 fps, 2 fps + frame time, 3 everything (cpu, physics,
## draws, primitives, renderer, GPU). PERF_NAMES is the settings row.
const PERF_NAMES := ["Off", "FPS", "FPS + frame time", "Full"]
## Graphics > Renderer. Godot picks its renderer at startup and cannot switch it while running, so a
## change restarts this process once (see relaunch_with_renderer). Auto = whatever the build was
## exported with.
const RENDERER_NAMES := ["Auto (build default)", "Forward+", "Mobile", "Compatibility"]
const RENDERER_IDS := ["", "forward_plus", "mobile", "gl_compatibility"]
const RENDERER_MARKER := "--renderer-set" # travels in the user args of the relaunched process
var renderer_choice := 0
var perf_overlay := 3

var show_fps: bool:
	get:
		return perf_overlay > 0
var music_vol := 1.0
var ui_vol := 1.0
var shadow_quality := 0 # SHADOWS_AUTO follows Graphics; then Off/Low/Medium/High
var crosshair_color := 0 # index into CROSSHAIR_COLORS
var crosshair_style := 0 # CROSSHAIR_STYLES
var crosshair_size := 1.0 # 0.5 .. 2.0
var show_minimap := true
var show_killfeed := true
var colorblind := 0 # COLORBLIND_NAMES
var reduce_shake := false
## Local speed feel: FOV kick, speed lines, landing camera dip and wind, all scaled with the
## player's own horizontal speed. Visual only, off keeps the old sprint FOV. See Player.SPEED_*.
var speed_fx := true
var _saved_keys: Dictionary = {} # action -> "k:<physical keycode>" / "m:<mouse button>" from settings.cfg
var view_sway := 2 # viewmodel sway and landing dip: 0 off, 1 reduced, 2 full (visual only)
var gfx_quality := 2 # Gfx.LOW/MEDIUM/HIGH: sky stays, SSAO/glow/fog/world paint scale down
var invert_y := false
var preferred_team := 0 # 0 Blue, 1 Orange — chosen in the menu
var pending_names: Dictionary = {} # peer_id → name, filled before spawn if the client RPCs first
var pending_teams: Dictionary = {} # peer_id → team, from join RPC
var net_hp: Dictionary = {} # server copy of HP, keyed by peer_id (bots included)
var _regen_dirty: Dictionary = {} # peer_id -> hp changed by regen since the last sync_regen
var _regen_sync_t := 0.0
var _hitstopping := false
var _round_music: AudioStreamPlayer
## Tension cues (Music bus): one build-up when a round goes live, one loop for the final stretch.
## Every machine decides the final stretch itself from the synced clock and scores, so all hear it.
const TENSION_TIME_LEFT := 30.0 # seconds left on the round clock
const TENSION_KILLS_LEFT := 3 # leader (FFA player / TDM team) this close to kill_limit
const TENSION_FADE := 1.2
const TENSION_START_LEN := 5.0 # round seconds after which the start build-up fades out
var menu_match := true # main.gd: the menu's background bot match stays quiet; the game boots into the menu
var _tension: AudioStreamPlayer
var _tension_final := false # final cue already started this round
var _tension_start_stream: AudioStream
var _tension_final_stream: AudioStream
var _tension_fade: Tween
## Calm loop while the home menu is up (over its silent background bot match). Fades with the menu.
const MENU_MUSIC_DB := -6.0
const MENU_FADE := 1.5 # fade out into a match / back in on return
const MENU_FADE_IN_BOOT := 0.35 # first show of the menu: audible at once
var _menu_music: AudioStreamPlayer
var _menu_music_on := false
var _menu_fade: Tween
var _tension_live := false # last tick: a round was being played
var _grenade_seq := 0
var _grenade_visuals: Dictionary = {}
var _grenade_pred_seq := 0
var _grenade_predicted: Dictionary = {} # client seq → predicted Grenade (thrower only), until the server spawn adopts it
var _grenade_done: Dictionary = {} # net_id → true once it exploded; late unreliable poses are ignored
var _rc_seq := 0
var _rc_done: Dictionary = {} # net_id → true once the car is gone; late poses must not move a ghost
var _fire_credit: Dictionary = {} # peer_id → {weapon_id: [credit_s, last_s]}

var scores: Dictionary = {}
var team_kills := [0, 0] # own counter, so leavers and trimmed bots do not take kills with them
var pings: Dictionary = {}
var _ping_accum := 0.0
var _round_timer := 0.0
var _round_active := false
var _match_state := 0
var _state_timer := 0.0


func is_networked() -> bool:
	return not is_offline


## Round-start freeze or final killcam: nobody moves, shoots, or throws.
func play_locked() -> bool:
	return round_frozen or killcam_active


## Humans are named by peer id; bots are `bot1` with peer_id -1, etc.
func player_for_peer(peer_id: int) -> Player:
	if peer_id == 0:
		return null
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null:
			continue
		if p.peer_id == peer_id or str(n.name) == str(peer_id):
			return p
		# Bot ids are negative only. A human id (host = 1) must never match `bot1`.
		if peer_id < 0 and p.is_bot and str(n.name) == "bot%d" % -peer_id:
			p.peer_id = peer_id
			return p
	return null


func is_ffa(m: int = -1) -> bool:
	var mm := mode if m < 0 else m
	return mm == MODE_FFA or mm == MODE_STYLE_FFA or mm == MODE_GUN_GAME


## True when this match fills bots per team instead of balancing one total.
func bot_split_active() -> bool:
	# A dedicated server always balances: it has no owner whose side the allies would be on, and the
	# per-side fill would keep every bot when humans join, so a public server would fill up with ten
	# bots plus ten players. Local and listen-host matches run the split.
	if is_dedicated:
		return false
	return not is_ffa() and bot_allies >= 0 and bot_enemies >= 0 and (bot_allies + bot_enemies) > 0


## Bots wanted on `team`: the allies sit on bot_team_base, everyone else is an enemy bot.
func bot_target(team: int) -> int:
	if bot_allies < 0:
		return -1
	return bot_allies if team == bot_team_base else bot_enemies


## #160: Capture the Flag.
func is_ctf(m: int = -1) -> bool:
	return (mode if m < 0 else m) == MODE_CTF


## Modes whose limit is fixed by the rules (menu hides the Kills row): Gun Game, CTF.
func has_fixed_limit(m: int = -1) -> bool:
	return is_gun_game(m) or is_ctf(m)


## #148: Gun Game (FFA weapon ladder).
func is_gun_game(m: int = -1) -> bool:
	return (mode if m < 0 else m) == MODE_GUN_GAME


## #82: style points, not kills, decide the round.
func is_style_mode(m: int = -1) -> bool:
	var mm := mode if m < 0 else m
	return mm == MODE_STYLE_TDM or mm == MODE_STYLE_FFA


## Points needed to win: kills, or style points in style modes.
static func style_limit_for(rate: int, round_sec: float) -> int:
	return rate * STYLE_UNIT * maxi(roundi(round_sec / 60.0), 1)


func score_limit() -> int:
	if is_gun_game():
		return GunGame.LADDER.size()
	if is_ctf():
		return CTF.CAPTURES_TO_WIN
	if is_style_mode():
		return style_limit_for(kill_limit, round_time)
	return kill_limit


## "kills" or "style" (HUD, scoreboard, menu blurbs).
func score_word() -> String:
	if is_gun_game():
		return "level"
	if is_ctf():
		return "captures"
	return "style" if is_style_mode() else "kills"


## Scoring, win checks, round clock and round reset live in MatchRules (shared/match_rules.gd).
func team_score(team_id: int) -> int:
	return MatchRules.team_score(self, team_id)


func player_score(peer_id: int) -> int:
	return MatchRules.player_score(self, peer_id)


func mode_name(m: int = -1) -> String:
	return MODE_NAMES[clampi(mode if m < 0 else m, 0, MODE_NAMES.size() - 1)]


## "TDM" for the menu chips; mode_name() stays the full name for the HUD and the lobby.
func mode_short_name(m: int = -1) -> String:
	return MODE_SHORT_NAMES[clampi(mode if m < 0 else m, 0, MODE_SHORT_NAMES.size() - 1)]


## One-line explanation for a mode chip's tooltip.
func mode_hint(m: int = -1) -> String:
	return MODE_HINTS[clampi(mode if m < 0 else m, 0, MODE_HINTS.size() - 1)]


## "ffa", "FFA", "free" or "2" → MODE_FFA. Unknown → -1.
static func parse_mode(raw: String) -> int:
	var s := raw.strip_edges().to_lower()
	if s in ["style-tdm", "style_tdm", "styletdm", "style", "style-team", "3"]:
		return MODE_STYLE_TDM
	if s in ["style-ffa", "style_ffa", "styleffa", "4"]:
		return MODE_STYLE_FFA
	if s in ["ctf", "capture-the-flag", "capture_the_flag", "flag", "6"]:
		return MODE_CTF
	if s in ["gungame", "gun-game", "gun_game", "gg", "5"]:
		return MODE_GUN_GAME
	if s in ["tdm", "team", "teams", "team_deathmatch", "1"]:
		return MODE_TDM
	if s in ["ffa", "free", "freeforall", "free_for_all", "dm", "2"]:
		return MODE_FFA
	return -1


func win_kills() -> int:
	return kill_limit


func default_kills_for(m: int = -1) -> int:
	return MatchRules.default_kills_for(self, m)


## Hostility for damage, bots, tags, and colours. FFA: everyone but yourself.
func is_enemy(a: Player, b: Player) -> bool:
	if a == null or b == null or a == b:
		return false
	if is_ffa():
		return true
	return a.team_id != b.team_id


## Same, by team ids and peers (kill feed, killcam ghosts, scoreboard rows).
func is_enemy_ids(team_a: int, team_b: int, peer_a: int = 0, peer_b: int = 1) -> bool:
	if is_ffa():
		return peer_a != peer_b
	return team_a != team_b


## Server → one client (join) or everyone: which map, mode, kill limit and round length this server runs.
@rpc("authority", "call_remote", "reliable", 0)
func sync_match_config(new_map: String, new_mode: int, kills: int = 0, time_sec: float = 0.0) -> void:
	if multiplayer.is_server():
		return
	set_match_config(StringName(new_map), new_mode, kills, time_sec)


func set_match_config(new_map: StringName, new_mode: int, kills: int = -1, time_sec: float = -1.0, bots: int = -1,
		allies: int = -1, enemies: int = -1) -> void:
	map_id = new_map if Maps.has(new_map) else Maps.DEFAULT
	mode = clampi(new_mode, MODE_TDM, MODE_LAST)
	if mode == MODE_CTF and not CTF.available(map_id):
		mode = MODE_TDM # #160: no flag bases on this map
	if mode == MODE_CTF:
		CTF.setup(self)
	CtfFlags.ensure(self) # #160: flag visuals only while CTF runs
	kill_limit = clampi(kills if kills >= KILLS_MIN else last_kills, KILLS_MIN, KILLS_MAX)
	round_time = time_sec if time_sec >= 60.0 else float(last_time_min * 60)
	round_time = clampf(round_time, float(TIME_MIN_MINUTES * 60), float(TIME_MAX_MINUTES * 60))
	bot_count = clampi(bots if bots >= 0 else last_bots, 0, BOT_COUNT_MAX)
	# Team modes may run an uneven match on purpose (you and a friend against ten bots). FFA has no
	# sides, so it always uses the single bot_count.
	if is_ffa() or allies < 0 or enemies < 0:
		bot_allies = -1
		bot_enemies = -1
	else:
		bot_allies = clampi(allies, 0, BOT_COUNT_MAX)
		bot_enemies = clampi(enemies, 0, BOT_COUNT_MAX)
	if match_config_handler.is_valid():
		match_config_handler.call(map_id, mode)


## Team of this machine's own pawn, -1 when there is none (menu, dedicated server).
func local_team() -> int:
	var me := player_for_peer(multiplayer.get_unique_id())
	return me.team_id if me else -1


func hp_of(p: Player) -> float:
	return Combat.hp_of(self, p)


## Authority: damage taken per life, by attacker (#64). victim -> attacker -> [damage, hits].
var _dmg_log: Dictionary = {}


func note_damage(attacker_peer: int, victim_peer: int, amount: float) -> void:
	Combat.note_damage(self, attacker_peer, victim_peer, amount)


func send_death_report(killer_peer: int, victim_peer: int, weapon_id: StringName = &"") -> void:
	Combat.send_death_report(self, killer_peer, victim_peer, weapon_id)


@rpc("authority", "call_remote", "reliable", 2)
func sync_death_report(args: Array) -> void:
	if args.size() >= 7:
		_show_death_report(args)


func _show_death_report(a: Array) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.show_death_report(str(a[0]), int(a[1]), int(a[2]), int(a[3]), int(a[4]), int(a[5]), str(a[6]).left(32))


func set_hp(p: Player, value: float) -> void:
	p.hp = value
	if is_networked() and p.peer_id != 0:
		net_hp[p.peer_id] = value


func clear_peer_hp(peer_id: int) -> void:
	Combat.clear_peer_hp(self, peer_id)


## Removes a scoreboard row on every machine. Team totals live in team_kills and stay.
func drop_score(peer_id: int) -> void:
	scores.erase(peer_id)
	if is_networked() and multiplayer.is_server():
		sync_score_removed.rpc(peer_id)


@rpc("authority", "call_remote", "reliable", 0)
func sync_score_removed(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	scores.erase(peer_id)
	pings.erase(peer_id)


func clean_name(n: String, fallback: String = "Player") -> String:
	return Lobby.clean_name(self, n, fallback)


func unique_name(peer_id: int, n: String) -> String:
	return Lobby.unique_name(self, peer_id, n)


func local_resolved_name() -> String:
	return Lobby.local_resolved_name(self)


func weapon_def(weapon_id: StringName) -> WeaponDef:
	return WEAPON_DEFS.get(weapon_id) as WeaponDef


const _KILL_SOURCE_NAMES := {
	&"grenade": "Grenade", &"knife": "Throwing Knife", &"melee": "Knife", &"rcxd": RCXD_DISPLAY_NAME, &"fall": "Fall",
}


## Name for a kill source as players see it: a gun's display_name, else grenade/knife/RC-XD/streaks.
func weapon_display_name(weapon_id: StringName) -> String:
	if weapon_id == &"":
		return ""
	var d := weapon_def(weapon_id)
	if d:
		return d.display_name
	if _KILL_SOURCE_NAMES.has(weapon_id):
		return str(_KILL_SOURCE_NAMES[weapon_id])
	return String(weapon_id).replace("_", " ").capitalize()


## Client → server fire. Hits resolve here; tracers/sfx go back out via broadcast_shot_fx.
## The server checks: equipped gun, fire rate, freeze, and that the shot starts near our copy of the shooter.
## `shot_seed` makes the server's pellets the same as the client's tracers.
@rpc("any_peer", "call_remote", "reliable", 1)
func request_weapon_fire(
	origin: Vector3,
	look_dir: Vector3,
	weapon_id: StringName,
	muzzle_pos: Vector3 = Vector3.ZERO,
	spread_mult: float = 1.0,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0,
	mag: int = 0,
	view_ms: int = 0
) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var shooter := player_for_peer(peer)
	if shooter == null or shooter.is_dead or shooter.is_bot or play_locked():
		return
	if shooter.weapon == null or shooter.weapon.def == null or shooter.weapon.def.id != weapon_id:
		return
	if not shooter.has_weapon(weapon_id): # not in their class
		return
	var def := shooter.weapon.def
	if look_dir.length_squared() < 0.0001 or not origin_plausible(shooter, origin):
		return
	if not _take_fire_credit(peer, def):
		return
	var floor_mult := def.spread_mult_for(shooter.min_spread_multiplier(), scoped)
	var mult := clampf(spread_mult, floor_mult, SPREAD_MAX)
	# Lag compensation (#105): cast against the targets where this client saw them, then put them back.
	_shot_rewind = LagComp.offsets_for(self, shooter, LagComp.rewind_ms_for(self, peer, view_ms))
	var best := _resolve_weapon_fire(shooter, origin, look_dir, def, mult, shot_seed, scoped, burst, mag, true)
	_shot_rewind = []
	if best.get("refused", false):
		return # empty magazine and no finished reload: no hit, no tracer (B4)
	var from := muzzle_pos
	if from == Vector3.ZERO or from.distance_to(origin) > 2.0:
		from = origin
	broadcast_shot_fx(from, best.get("end", origin + look_dir.normalized() * def.range_m), peer)
	if best.get("hit", false):
		notify_hit.rpc_id(peer, best.killed, best.headshot)


func origin_plausible(shooter: Player, origin: Vector3) -> bool:
	return Combat.origin_plausible(self, shooter, origin)


func _take_fire_credit(peer: int, def: WeaponDef) -> bool:
	return Combat.take_fire_credit(self, peer, def)


func next_grenade_id() -> int:
	return Throwables.next_grenade_id(self)


func throw_grenade(thrower: Player, origin: Vector3, dir: Vector3, client_seq := 0) -> void:
	Throwables.throw_grenade(self, thrower, origin, dir, client_seq)


func predict_grenade(thrower: Player, origin: Vector3, dir: Vector3) -> int:
	return Throwables.predict_grenade(self, thrower, origin, dir)


## Client throw. Server re-checks ammo, death, and freeze.
@rpc("any_peer", "call_remote", "reliable", 1)
func request_grenade(origin: Vector3, dir: Vector3, client_seq: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var thrower := player_for_peer(peer)
	if thrower == null or dir.length_squared() < 0.0001 or not origin_plausible(thrower, origin):
		return
	throw_grenade(thrower, origin, dir, client_seq)


@rpc("authority", "call_local", "reliable", 0)
func sync_grenade_count(peer_id: int, n: int) -> void:
	var p := player_for_peer(peer_id)
	if p == null:
		return
	p.grenades = n
	p._notify_grenades()


## Visual copy on clients, flying on its own from the spawn velocity. Damage stays on the server grenade.
## The thrower's own predicted copy is adopted instead of spawning a second one.
@rpc("authority", "call_remote", "reliable", 1)
func sync_grenade_spawn(net_id: int, pos: Vector3, vel: Vector3, thrower_peer: int, client_seq: int) -> void:
	if multiplayer.is_server() or _grenade_done.has(net_id):
		return
	if thrower_peer == multiplayer.get_unique_id() and _grenade_predicted.has(client_seq):
		var pred = _grenade_predicted[client_seq]
		_grenade_predicted.erase(client_seq)
		if is_instance_valid(pred):
			_grenade_visuals[net_id] = pred
			return
	var existing = _grenade_visuals.get(net_id)
	if is_instance_valid(existing):
		(existing as Grenade).velocity = vel # a pose beat the spawn here; give it the real arc
		return
	_grenade_visual(net_id, pos, vel)


@rpc("authority", "call_remote", "unreliable", 1)
func sync_grenade_pose(net_id: int, pos: Vector3) -> void:
	# Unreliable can arrive after the reliable boom; that would leave a ghost grenade.
	if multiplayer.is_server() or _grenade_done.has(net_id):
		return
	var g := _grenade_visual(net_id, pos, Vector3.ZERO) as Grenade
	if g:
		g.apply_net_pose(pos)


## Drop the flying mesh, then play the same boom the server already showed.
@rpc("authority", "call_remote", "reliable", 1)
func sync_grenade_boom(pos: Vector3, net_id: int) -> void:
	if multiplayer.is_server():
		return
	_grenade_done[net_id] = true
	if _grenade_visuals.has(net_id):
		var vis: Node = _grenade_visuals[net_id]
		_grenade_visuals.erase(net_id)
		if is_instance_valid(vis):
			vis.queue_free()
	Grenade.play_boom(pos)


func _grenade_visual(net_id: int, pos: Vector3, vel: Vector3) -> Node3D:
	return Throwables.grenade_visual(self, net_id, pos, vel)


# --- Throwing knives (grenade slot, F). Same flow as grenades: authority decides, clients get copies. ---

func throw_knife(thrower: Player, origin: Vector3, dir: Vector3) -> void:
	Throwables.throw_knife(self, thrower, origin, dir)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_knife(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var thrower := player_for_peer(peer)
	if thrower == null or thrower.is_bot or dir.length_squared() < 0.0001 or not origin_plausible(thrower, origin):
		return
	throw_knife(thrower, origin, dir)


@rpc("authority", "call_local", "reliable", 0)
func sync_knife_count(peer_id: int, n: int) -> void:
	var p := player_for_peer(peer_id)
	if p == null:
		return
	p.knives = n
	p._notify_grenades()


## Clients fly a visual copy from the release; sync_knife_done ends it where the server says.
@rpc("authority", "call_remote", "reliable", 1)
func sync_knife_spawn(net_id: int, pos: Vector3, vel: Vector3) -> void:
	if multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var k := ThrowingKnife.new()
	k.is_visual = true
	k.velocity = vel
	k.origin = pos
	scene.add_child(k)
	k.global_position = pos
	_knife_visuals[net_id] = k


## `end`: ThrowingKnife.END_* (stuck in the world at `pos` for a moment, hit a body, or flew off).
@rpc("authority", "call_remote", "reliable", 0)
func sync_knife_done(net_id: int, pos: Vector3, normal: Vector3, end: int) -> void:
	if multiplayer.is_server():
		return
	var k := _knife_visuals.get(net_id) as ThrowingKnife
	_knife_visuals.erase(net_id)
	if k == null or not is_instance_valid(k):
		return
	if end == ThrowingKnife.END_STUCK:
		k.stick(pos, normal)
		return
	k.global_position = pos
	if end == ThrowingKnife.END_BODY:
		k.play_flesh()
	k.queue_free()


func knife_hit(knife: ThrowingKnife, victim: Player, point: Vector3, normal: Vector3) -> void:
	Throwables.knife_hit(self, knife, victim, point, normal)


func fire_weapon_locally(
	shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float = 1.0,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0,
	mag: int = 0
) -> Dictionary:
	return Combat.fire_weapon_locally(self, shooter, origin, look_dir, def, spread_mult, shot_seed, scoped, burst, mag)


func _resolve_weapon_fire(
	shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0,
	mag: int = 0,
	strict_mag: bool = false
) -> Dictionary:
	return Combat.resolve_weapon_fire(self, shooter, origin, look_dir, def, spread_mult, shot_seed, scoped, burst, mag, strict_mag)


func _resolve_shot_rays(
	shooter: Player, origin: Vector3, look_dir: Vector3, def: WeaponDef, spread_mult: float, shot_seed: int
) -> Dictionary:
	return Combat.resolve_shot_rays(self, shooter, origin, look_dir, def, spread_mult, shot_seed)


func _burst_for(shooter: Player, def: WeaponDef, seq: int) -> Dictionary:
	return Combat.burst_for(self, shooter, def, seq)


func _mag_for(shooter: Player, def: WeaponDef, seq: int) -> Dictionary:
	return Combat.mag_for(self, shooter, def, seq)


## Melee: the swing is the "shot" for the movement tricks (SURF / DROP KILL).
func begin_melee_ctx(attacker: Player, origin: Vector3) -> void:
	_shot_ctx = {"shooter": attacker, "origin": origin, "scoped": false, "burst": {}}


func end_melee_ctx() -> void:
	_shot_ctx = {}


func shot_exclude(shooter: Player) -> Array[RID]:
	return Combat.shot_exclude(self, shooter)


func _merge_hit_result(best: Dictionary, result: Dictionary) -> Dictionary:
	return Combat.merge_hit_result(self, best, result)


func spread_dir(forward: Vector3, deg: float, rng: RandomNumberGenerator) -> Vector3:
	return Combat.spread_dir(self, forward, deg, rng)


func _apply_shot_hit(shooter: Player, hit: Dictionary, damage: float, def: WeaponDef) -> Dictionary:
	return Combat.apply_shot_hit(self, shooter, hit, damage, def)


@rpc("authority", "call_remote", "reliable", 1)
func notify_hit(killed: bool, headshot: bool) -> void:
	hit_confirmed.emit(killed, headshot)


@rpc("any_peer", "call_remote", "reliable", 0)
func submit_display_name(n: String, team: int = -1) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	n = unique_name(peer, n)
	pending_names[peer] = n
	if team == TEAM_A or team == TEAM_B:
		pending_teams[peer] = team
	if in_lobby:
		set_lobby_member(peer, n, int(pending_teams.get(peer, preferred_team)))
		return
	apply_display_name.rpc(peer, n)


## Also writes the scoreboard name. Spawn often happens before the client's name RPC, but on a
## dedicated server the name can also win the race: then there is no pawn yet and the row would be
## made with team 0. The pawn's team wins when it exists, then the row's, then the joiner's pick;
## register_participant corrects the team again when the pawn spawns.
@rpc("authority", "call_local", "reliable", 0)
func apply_display_name(peer_id: int, n: String) -> void:
	var p := player_for_peer(peer_id)
	var team := int(pending_teams.get(peer_id, 0))
	var kills := 0
	if scores.has(peer_id):
		kills = int(scores[peer_id].kills)
		team = int(scores[peer_id].get("team", team))
	if p:
		p.set_display_name(n)
		team = p.team_id
	_apply_score(peer_id, kills, n, team)


## `from_pos`: where the damage came from (shooter, melee attacker, grenade blast) for the
## victim's damage direction indicator. Vector3.INF when unknown.
@rpc("authority", "call_local", "reliable", 1)
func broadcast_hurt(peer_id: int, new_hp: float, killed: bool, from_pos: Vector3 = Vector3.INF) -> void:
	var p := player_for_peer(peer_id)
	if p:
		p.apply_hurt_state(new_hp, killed, from_pos)


func respawn_pawn(p: Player) -> void:
	Combat.respawn_pawn(self, p)


func _reroll_bot_gun(p: Player) -> void:
	Combat.reroll_bot_gun(self, p)


## `xform`: the spawn point the server picked (FFA picks a new one every time).
@rpc("authority", "call_local", "reliable", 0)
func broadcast_respawn(peer_id: int, xform: Transform3D) -> void:
	var p := player_for_peer(peer_id)
	if p:
		p._spawn_xform = xform
		p.apply_respawn_state()


func take_pending_name(peer_id: int, fallback: String) -> String:
	return Lobby.take_pending_name(self, peer_id, fallback)


func _is_match_authority() -> bool:
	return not is_networked() or multiplayer.is_server()


func _display_name_for(peer_id: int) -> String:
	return Lobby.display_name_for(self, peer_id)


func _apply_score(peer_id: int, kills: int, n: String, team: int = 0) -> void:
	if not scores.has(peer_id):
		scores[peer_id] = {"name": n, "kills": 0, "team": team, "style": 0, "deaths": 0}
	scores[peer_id].kills = kills
	scores[peer_id].name = n
	scores[peer_id].team = team
	score_changed.emit(peer_id, kills, n)


func register_participant(peer_id: int, n: String, team: int = 0) -> void:
	Lobby.register_participant(self, peer_id, n, team)


const CHAT_MAX := 120


func send_chat(text: String) -> void:
	Lobby.send_chat(self, text)


func _local_team() -> int:
	var p := player_for_peer(multiplayer.get_unique_id() if is_networked() else 1)
	return p.team_id if p else 0


func _relay_chat(peer_id: int, text: String) -> void:
	Lobby.relay_chat(self, peer_id, text)


## Client → server. Strip/cap here again in case of a bad peer.
@rpc("any_peer", "call_remote", "reliable", 2)
func submit_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	text = text.strip_edges()
	if text.length() > CHAT_MAX:
		text = text.substr(0, CHAT_MAX)
	if text == "":
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	_relay_chat(peer, text)


## call_local so the listen-server HUD sees the line too.
@rpc("authority", "call_local", "reliable", 2)
func broadcast_chat(n: String, team: int, text: String) -> void:
	_deliver_chat(n, team, text)


func _deliver_chat(n: String, team: int, text: String) -> void:
	Lobby.deliver_chat(self, n, team, text)


func set_lobby_member(peer_id: int, n: String, team: int) -> void:
	Lobby.set_lobby_member(self, peer_id, n, team)


func remove_lobby_member(peer_id: int) -> void:
	Lobby.remove_lobby_member(self, peer_id)


func _push_lobby() -> void:
	Lobby.push_lobby(self)


@rpc("authority", "call_remote", "reliable", 0)
func sync_lobby(data: Dictionary) -> void:
	if multiplayer.is_server():
		return
	lobby = data
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable", 0)
func request_lobby_team(team: int) -> void:
	if not multiplayer.is_server() or not in_lobby:
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	if not lobby.has(peer):
		return
	lobby[peer].team = clampi(team, TEAM_A, TEAM_B)
	pending_teams[peer] = int(lobby[peer].team)
	_push_lobby()


@rpc("authority", "call_local", "reliable", 0)
func begin_match() -> void:
	in_lobby = false
	match_starting.emit()


func announce_presence(player_name: String, joined: bool, team: int) -> void:
	Lobby.announce_presence(self, player_name, joined, team)


@rpc("authority", "call_remote", "reliable", 0)
func sync_presence(player_name: String, joined: bool, team: int) -> void:
	if multiplayer.is_server():
		return
	presence.emit(player_name, joined, team)


func register_kill(
	killer_peer_id: int, victim_peer_id: int, weapon_id: StringName = &"rifle", headshot: bool = false
) -> void:
	Combat.register_kill(self, killer_peer_id, victim_peer_id, weapon_id, headshot)


func _register_suicide(peer_id: int, weapon_id: StringName) -> void:
	Combat.register_suicide(self, peer_id, weapon_id)


func _add_team_kill(team_id: int) -> void:
	Combat.add_team_kill(self, team_id)


@rpc("authority", "call_remote", "reliable", 0)
func sync_team_kills(blue: int, orange: int) -> void:
	team_kills = [blue, orange]


const STREAK_AT := 3 # UAV
const RCXD_AT := 5
## Player-facing name of the RC-XD streak (#146). Internal ids (rcxd, CHARGE_RCXD) stay as they are.
const RCXD_DISPLAY_NAME := "RCXplodie"
const RADAR_TIME := 25.0 # UAV: enemies on the minimap this long (BO2 is ~30 s)
const CHARGE_RADAR := 1
const CHARGE_RCXD := 2
const LOS_AT := 7 # hands detach
const CHARGE_LOS := 4

signal flags_changed # #160: flag state or capture score changed
signal flag_event(kind: String, team: int, by_name: String) # #160: taken / dropped / returned / captured
signal streak_used(peer_id: int, slot: int) # authority: a UAV (0), RC-XD (1) or LOS (2) was spent
var streak_progress: Dictionary = {} # peer -> kills this life (death clears this)
var streak_charges: Dictionary = {} # peer -> bitmask of streaks earned and not yet used
var streak_earned: Dictionary = {} # peer -> bitmask already passed this life (stops a second copy)


func _bump_streak(killer_peer_id: int, victim_peer_id: int) -> void:
	Streaks.bump_streak(self, killer_peer_id, victim_peer_id)


func _push_streak(peer_id: int) -> void:
	Streaks.push_streak(self, peer_id)


@rpc("authority", "call_remote", "reliable", 0)
func sync_streak(n: int, charges: int, earned: int) -> void:
	_apply_streak_local(n, charges, earned)


func _apply_streak_local(n: int, charges: int, earned: int) -> void:
	Streaks.apply_streak_local(self, n, charges, earned)


func try_activate_streak(peer_id: int, slot: int) -> void:
	Streaks.try_activate_streak(self, peer_id, slot)


## HUD calls this. Clients cannot grant their own UAV.
func request_use_streak(slot: int) -> void:
	if is_networked() and not multiplayer.is_server():
		request_streak.rpc_id(1, slot)
	else:
		var id := multiplayer.get_unique_id() if is_networked() else 1
		try_activate_streak(id, slot)


@rpc("any_peer", "call_remote", "reliable", 1)
func request_streak(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	try_activate_streak(peer, slot)


func next_rc_id() -> int:
	_rc_seq += 1
	return _rc_seq


func mark_rc_done(net_id: int) -> void:
	_rc_done[net_id] = true


## Driver's aim (where the car should head; it turns toward it) and throttle. The server car is the one that explodes.
@rpc("any_peer", "call_remote", "unreliable", 1)
func rc_drive(net_id: int, yaw_in: float, throttle_in: float) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var car := RcXd.authority_by_id(net_id)
	if car == null or car.owner_peer != peer:
		return
	car.apply_remote_input(yaw_in, throttle_in)


@rpc("any_peer", "call_remote", "reliable", 1)
func rc_detonate(net_id: int) -> void:
	if not multiplayer.is_server() or play_locked():
		return
	var peer := multiplayer.get_remote_sender_id()
	var car := RcXd.authority_by_id(net_id)
	if car == null or car.owner_peer != peer:
		return
	car.shutdown(true)


## Blast push for one player, sent to the machine that simulates that pawn.
@rpc("authority", "call_remote", "reliable", 1)
func sync_knockback(peer_id: int, impulse: Vector3) -> void:
	var p := player_for_peer(peer_id)
	if p and p.is_local():
		p.add_knockback(impulse)


## Blast push for the driver's predicted RC-XD copy (the server car got it already).
@rpc("authority", "call_remote", "reliable", 1)
func sync_rc_kick(net_id: int, impulse: Vector3) -> void:
	var car := RcXd.by_id(net_id)
	if car and car.predict:
		car.add_kick(impulse)


## Visual copy on clients. The driver's copy simulates; the rest follow poses.
@rpc("authority", "call_remote", "reliable", 1)
func sync_rc_spawn(net_id: int, peer: int, team: int, pos: Vector3, yaw_in: float) -> void:
	if multiplayer.is_server() or _rc_done.has(net_id):
		return
	RcXd.spawn_visual(net_id, peer, team, pos, yaw_in)


@rpc("authority", "call_remote", "unreliable", 1)
func sync_rc_pose(net_id: int, pos: Vector3, yaw_in: float, life_in: float, vel_in: Vector3) -> void:
	if multiplayer.is_server() or _rc_done.has(net_id):
		return
	var car := RcXd.by_id(net_id)
	if car:
		car.apply_net_pose(pos, yaw_in, life_in, vel_in)


@rpc("authority", "call_remote", "reliable", 1)
func sync_rc_end(net_id: int, pos: Vector3, exploded: bool) -> void:
	if multiplayer.is_server():
		return
	_rc_done[net_id] = true
	var car := RcXd.by_id(net_id)
	if car:
		car.client_end(exploded, pos)
	elif exploded and not is_dedicated:
		Grenade.play_boom(pos, true)


@rpc("authority", "call_remote", "reliable", 1)
func sync_rc_hp(net_id: int, value: float) -> void:
	if multiplayer.is_server():
		return
	var car := RcXd.by_id(net_id)
	if car:
		car.apply_hp(value)


## LOS hands. The server spawns them; everyone else builds a visual. Poses are unreliable on purpose:
## a lost packet must not stall the channel. The bash is reliable and only the server resolves it.
@rpc("authority", "call_remote", "reliable", 1)
func sync_los_spawn(peer: int, pos: Vector3, yaw_in: float, pitch_in: float) -> void:
	if multiplayer.is_server():
		return
	LosHands.spawn_remote(peer, pos, yaw_in, pitch_in)


@rpc("authority", "call_remote", "unreliable", 1)
func sync_los_pose(peer: int, pos: Vector3, vel: Vector3, yaw_in: float, pitch_in: float) -> void:
	if multiplayer.is_server():
		return
	LosHands.apply_pose(peer, pos, vel, yaw_in, pitch_in)


@rpc("authority", "call_remote", "reliable", 1)
func sync_los_end(peer: int, snap_to: Vector3 = Vector3.INF) -> void:
	if multiplayer.is_server():
		return
	LosHands.abort_for(peer, snap_to)


## Owner → server, every physics tick. Wish is world space and follows the look, including up.
@rpc("any_peer", "call_remote", "unreliable", 1)
func los_input(wish: Vector3, yaw_in: float, pitch_in: float) -> void:
	if not multiplayer.is_server():
		return
	LosHands.server_input(multiplayer.get_remote_sender_id(), wish, yaw_in, pitch_in)


## Owner → server. The origin has to be the hands, not the body's eye (that check would reject it).
@rpc("any_peer", "call_remote", "reliable", 1)
func los_melee(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	LosHands.server_swing(multiplayer.get_remote_sender_id(), origin, dir)


## Owner → server. Stop the hands now, without a snap (the streak key again). Reliable: a lost
## recall would leave the client standing with no hands for the rest of the window.
@rpc("any_peer", "call_remote", "reliable", 1)
func los_recall() -> void:
	if not multiplayer.is_server():
		return
	LosHands.server_recall(multiplayer.get_remote_sender_id())


## Same popup split as the radar: your team sees RC-XD, the other team sees ENEMY RC-XD.
func announce_rc(peer_id: int, team: int) -> void:
	var by := _display_name_for(peer_id)
	if scores.has(peer_id):
		by = str(scores[peer_id].name)
	if is_networked():
		sync_rc_announce.rpc(team, by, peer_id)
	_apply_rc_announce(team, by, peer_id)


@rpc("authority", "call_remote", "reliable", 2)
func sync_rc_announce(team: int, by_name: String, by_peer: int) -> void:
	if multiplayer.is_server():
		return
	_apply_rc_announce(team, by_name, by_peer)


func _apply_rc_announce(team: int, by_name: String, by_peer: int) -> void:
	var mine := local_team()
	if mine < 0:
		return
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud == null:
		return
	var friendly := team == mine
	if is_ffa():
		friendly = by_peer == multiplayer.get_unique_id()
	hud.show_rc_event(by_name, team, friendly)


func _grant_radar(peer_id: int) -> void:
	Streaks.grant_radar(self, peer_id)


@rpc("authority", "call_remote", "reliable", 2)
func sync_uav_spawn(id: int, team: int, peer: int, c: Vector3, r: float, h: float, phase: float, seconds: float) -> void:
	if multiplayer.is_server():
		return
	UavDrone.spawn(self, id, team, peer, c, r, h, phase, clampf(seconds, 0.0, RADAR_TIME), false)


## Authority: drone `d` reached 0 HP from `shooter_peer`. Kill feed, notice, early radar end everywhere.
func uav_shot_down(d: UavDrone, shooter_peer: int, shooter_team: int, weapon_id: StringName) -> void:
	var shooter := _display_name_for(shooter_peer)
	if scores.has(shooter_peer):
		shooter = str(scores[shooter_peer].name)
	_emit_kill_feed(shooter, "UAV", weapon_id, shooter_team, d.team, "")
	if is_networked():
		sync_kill_feed.rpc(shooter, "UAV", String(weapon_id), shooter_team, d.team, "")
		sync_uav_end.rpc(d.net_id, d.team, d.owner_peer, shooter_peer)
	_uav_end(d.net_id, d.team, d.owner_peer, shooter_peer)


@rpc("authority", "call_remote", "reliable", 2)
func sync_uav_end(id: int, team: int, owner_peer: int, shooter_peer: int) -> void:
	if multiplayer.is_server():
		return
	_uav_end(id, team, owner_peer, shooter_peer)


func _uav_end(id: int, team: int, owner_peer: int, shooter_peer: int) -> void:
	var d := UavDrone.by_id(id)
	if d:
		d.shoot_down()
	Streaks.uav_down(self, team, owner_peer)
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud and shooter_peer == multiplayer.get_unique_id():
		hud.show_notice("UAV neergeschoten", 2.5)


@rpc("authority", "call_remote", "reliable", 2)
func sync_radar(team: int, by_name: String, seconds: float, by_peer: int) -> void:
	if multiplayer.is_server():
		return
	_apply_radar(team, by_name, clampf(seconds, 0.0, RADAR_TIME), by_peer)


func _apply_radar(team: int, by_name: String, seconds: float, by_peer: int) -> void:
	Streaks.apply_radar(self, team, by_name, seconds, by_peer)


func clear_radar() -> void:
	Streaks.clear_radar(self)


func _emit_kill_feed(
	killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int, tricks: String
) -> void:
	kill_feed.emit(killer_name, victim_name, weapon_id, killer_team, victim_team, tricks)


@rpc("authority", "call_remote", "reliable", 2)
func sync_kill_feed(
	killer_name: String, victim_name: String, weapon_id: String, killer_team: int, victim_team: int, tricks: String = ""
) -> void:
	if multiplayer.is_server():
		return
	kill_feed.emit(killer_name, victim_name, StringName(weapon_id), killer_team, victim_team, tricks.left(80))


# --- Trickshots / style (see Style). Match authority decides, everyone shows it. ---

## Trick detection lives in Tricks (shared/tricks.gd); these wrappers keep the old entry points.
func _detect_tricks(
	killer_peer_id: int, victim_peer_id: int, weapon_id: StringName, headshot: bool = false
) -> Array[StringName]:
	return Tricks.detect(self, killer_peer_id, victim_peer_id, weapon_id, headshot)


func _note_trick_history(killer_peer_id: int, victim_peer_id: int, weapon_id: StringName, headshot: bool) -> void:
	Tricks.note_history(_hs_streak, _shotgun_kill_t, _shot_ctx, killer_peer_id, victim_peer_id, weapon_id, headshot)


## Style awarding lives in ComboLedger (shared/combo_ledger.gd); wrapper keeps the old entry point.
func _award_style(kill_info: Dictionary, tricks_in: Array[StringName]) -> void:
	ComboLedger.award_style(self, kill_info, tricks_in)


@rpc("authority", "call_remote", "reliable", 2)
func sync_trick(
	killer_peer_id: int, victim_peer_id: int, tricks: String, points: int, multiplier: float, total: int,
	trick_id: int, is_best: bool
) -> void:
	if multiplayer.is_server():
		return
	_apply_trick(killer_peer_id, victim_peer_id, tricks, points, multiplier, total, trick_id, is_best)


## `is_best`: the round's new best trick, so every machine keeps its replay for the final killcam.
func _apply_trick(
	killer_peer_id: int, victim_peer_id: int, tricks: String, points: int, multiplier: float, total: int,
	trick_id: int, is_best: bool
) -> void:
	if scores.has(killer_peer_id):
		scores[killer_peer_id].style = maxi(total, 0)
	if is_best and killcam:
		killcam.note_trick(trick_id, victim_peer_id)
	trick_scored.emit(killer_peer_id, tricks, points, multiplier, total)
	if _is_match_authority():
		_check_style_win(killer_peer_id)
	if scores.has(killer_peer_id):
		score_changed.emit(killer_peer_id, int(scores[killer_peer_id].kills), str(scores[killer_peer_id].name))


## What the final killcam replays: the round's best trickshot if there was one (with the last kill as
## fallback for machines that have no replay of it), else the last kill.
func killcam_pick() -> Dictionary:
	if best_trick.is_empty():
		return final_kill
	var info := best_trick.duplicate()
	info["fallback"] = final_kill.duplicate()
	return info


func style_king() -> Dictionary:
	return MatchRules.style_king(scores)


# ---------------------------------------------------------------------------------------------
# #84 combos (match authority). Players report moves through Game.combo_move from their style track.

var _combos: Dictionary = {} # peer -> Combo state


## Combo logic lives in ComboLedger; these wrappers keep the old entry points (and RPCs stay here).
func combo_move(peer_id: int, move: StringName) -> void:
	ComboLedger.move(self, peer_id, move)


func combo_of(peer_id: int) -> Dictionary:
	return _combos.get(peer_id, {})


func _combo_end(peer_id: int, state: String, banked: int) -> void:
	ComboLedger.end(self, peer_id, state, banked)


## #160: authority runs the flags; clients only count the dropped-flag timer down for the HUD.
func _tick_ctf(delta: float) -> void:
	if not is_ctf():
		return
	if _is_match_authority():
		CTF.tick(self, delta)
		return
	for f in flags:
		if int(f.state) == Objective.DROPPED:
			f.drop_t = maxf(float(f.drop_t) - delta, 0.0)


func _tick_combos(delta: float) -> void:
	ComboLedger.tick(self, delta)


func _send_combo(peer_id: int, c: Dictionary, state: String, banked: int) -> void:
	ComboLedger.send(self, peer_id, c, state, banked)


@rpc("authority", "call_remote", "reliable", 2)
func sync_combo(args: Array) -> void:
	if args.size() >= 6:
		_apply_combo(args)


func _apply_combo(a: Array) -> void:
	combo_changed.emit(int(a[0]), float(a[1]), float(a[2]), str(a[3]).left(120), str(a[4]), int(a[5]))


func _add_death(peer_id: int) -> void:
	Combat.add_death(self, peer_id)


## #B1: the server's copy of a remote pawn is the truth. A claim it refused puts the client back on it.
@rpc("authority", "call_remote", "reliable", 1)
func correct_position(peer_id: int, v: Vector3) -> void:
	var p := player_for_peer(peer_id)
	if p != null:
		p.apply_position_correction(v)


@rpc("authority", "call_remote", "reliable", 0)
func sync_deaths(peer_id: int, deaths: int) -> void:
	if scores.has(peer_id):
		scores[peer_id].deaths = maxi(deaths, 0)


## `style` -1 keeps the row's style (only the round reset sends 0).
@rpc("authority", "call_remote", "reliable", 0)
func sync_score(peer_id: int, score: int, n: String, team: int = 0, style: int = -1) -> void:
	_apply_score(peer_id, score, n, team)
	if style >= 0 and scores.has(peer_id):
		scores[peer_id].style = style


@rpc("authority", "call_remote", "reliable", 0)
func sync_round_end(winner_peer_id: int, winner_name: String, round_scores: Dictionary) -> void:
	_round_active = false # hides the HUD clock on clients too
	clear_radar()
	round_ended.emit(winner_peer_id, winner_name, round_scores)


@rpc("authority", "call_remote", "reliable", 2)
func sync_round_time(time_left: float) -> void:
	_round_timer = round_time - time_left
	_round_active = time_left > 0.0


@rpc("authority", "call_remote", "reliable", 0)
func sync_all_scores(scores_data: Array) -> void:
	for entry in scores_data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pid: int = int(entry.peer_id)
		var n: String = str(entry.name)
		var kills: int = int(entry.kills)
		var team: int = int(entry.get("team", 0))
		_apply_score(pid, kills, n, team)
		scores[pid].style = maxi(int(entry.get("style", 0)), 0)
		scores[pid].deaths = maxi(int(entry.get("deaths", 0)), 0)


func _check_win_team(team_id: int) -> void:
	MatchRules.check_win_team(self, team_id)


func _check_style_win(peer_id: int) -> void:
	MatchRules.check_style_win(self, peer_id)


func _check_win_player(peer_id: int) -> void:
	MatchRules.check_win_player(self, peer_id)


func _end_round_player(peer_id: int) -> void:
	MatchFlow.end_round_player(self, peer_id)


func _end_round_team(team_id: int) -> void:
	MatchFlow.end_round_team(self, team_id)


func notify_intermission() -> void:
	MatchFlow.notify_intermission(self)


@rpc("authority", "call_remote", "reliable", 0)
func sync_intermission() -> void:
	if multiplayer.is_server():
		return
	intermission_started.emit()


func set_round_frozen(on: bool) -> void:
	round_frozen = on
	if on:
		clear_radar()
	round_freeze_changed.emit(on)
	if on:
		play_round_sting()
		play_tension(false) # intermission over, countdown starts: build-up cue for everyone
	else:
		stop_round_sting()
	if is_networked() and multiplayer.is_server():
		sync_round_frozen.rpc(on)


@rpc("authority", "call_remote", "reliable", 0)
func sync_round_frozen(on: bool) -> void:
	if multiplayer.is_server():
		return
	round_frozen = on
	if on:
		_round_active = false
		clear_radar()
	round_freeze_changed.emit(on)
	if on:
		play_round_sting()
		play_tension(false) # intermission over, countdown starts: build-up cue for everyone
	else:
		stop_round_sting()


func play_round_sting() -> void:
	MatchAudio.play_round_sting(self)


func stop_round_sting() -> void:
	MatchAudio.stop_round_sting(self)


func _setup_tension_music() -> void:
	MatchAudio.setup_tension_music(self)


static func _cli_is_server() -> bool:
	return OS.get_cmdline_user_args().has("--server")


func _tick_menu_music(boot := false) -> void:
	MatchAudio.tick_menu_music(self, boot)


func play_tension(final: bool) -> void:
	MatchAudio.play_tension(self, final)


func stop_tension() -> void:
	MatchAudio.stop_tension(self)


func leader_kills() -> int:
	return MatchAudio.leader_kills(self)


func _tick_tension() -> void:
	MatchAudio.tick_tension(self)


func start_round() -> void:
	MatchFlow.start_round(self)


func _clear_round_streaks() -> void:
	Streaks.clear_round_streaks(self)


func end_freeze() -> void:
	MatchFlow.end_freeze(self)


func send_match_state(peer_id: int) -> void:
	MatchFlow.send_match_state(self, peer_id)


func reset_session() -> void:
	MatchFlow.reset_session(self)


func update_round_timer(delta: float) -> bool:
	return MatchRules.update_round_timer(self, delta)


func _get_leader() -> int:
	return MatchFlow.get_leader(self)


func top_player() -> int:
	return MatchFlow.top_player(self)


func get_team_kills(team_id: int) -> int:
	return int(team_kills[clampi(team_id, TEAM_A, TEAM_B)])


func get_scores() -> Array[Dictionary]:
	return MatchFlow.get_scores(self)


func _sort_scores(a: Dictionary, b: Dictionary) -> bool:
	if not is_ffa() and int(a.get("team", 0)) != int(b.get("team", 0)):
		return int(a.team) < int(b.team)
	var key := score_word()
	if int(a.get(key, 0)) == int(b.get(key, 0)):
		if key == "style" and a.kills != b.kills:
			return a.kills > b.kills
		return str(a.name) < str(b.name)
	return int(a.get(key, 0)) > int(b.get(key, 0))


func get_round_time_left() -> float:
	return maxf(round_time - _round_timer, 0.0)


func broadcast_shot_fx(from: Vector3, to: Vector3, shooter_peer_id: int) -> void:
	Combat.broadcast_shot_fx(self, from, to, shooter_peer_id)


## Skip the shooter: they already spawned tracers locally in Weapon._fire.
@rpc("authority", "call_remote", "unreliable", 2)
func sync_shot_fx(from: Vector3, to: Vector3, shooter_peer_id: int = 0) -> void:
	if shooter_peer_id != 0 and shooter_peer_id == multiplayer.get_unique_id():
		return
	_spawn_net_tracer(from, to)
	var shooter := player_for_peer(shooter_peer_id)
	if shooter and shooter.weapon:
		shooter.weapon.play_fire_sfx()
	_note_net_shot(from, to, shooter)


func _note_net_shot(from: Vector3, to: Vector3, shooter: Player) -> void:
	Combat.note_net_shot(self, from, to, shooter)


func _spawn_net_tracer(from: Vector3, to: Vector3) -> void:
	Combat.spawn_net_tracer(self, from, to)


func _sample_pings() -> void:
	MatchFlow.sample_pings(self)


@rpc("authority", "call_remote", "unreliable", 2)
## `server_ms` is the server clock when sent, for LagComp.view_ms (lag compensation, #105).
func sync_pings(data: Dictionary, server_ms: int = 0) -> void:
	if multiplayer.is_server():
		return
	pings = data
	LagComp.note_server_time(self, server_ms)


func _tick_lines(delta: float) -> void:
	MatchFlow.tick_lines(self, delta)


func _decay_line_clocks(delta: float) -> void:
	MatchFlow.decay_line_clocks(self, delta)


func award_move_trick(peer_id: int, trick: StringName) -> void:
	MatchFlow.award_move_trick(self, peer_id, trick)


func _award_line(peer_id: int, strip_name: String) -> void:
	MatchFlow.award_line(self, peer_id, strip_name)


## Listen-server: bots have MultiplayerSynchronizer off, so we push poses ourselves.
func _physics_process(delta: float) -> void:
	_tick_regen(delta)
	_tick_tension()
	_tick_lines(delta)
	_tick_combos(delta)
	_tick_ctf(delta)
	if radar_left > 0.0:
		radar_left = maxf(radar_left - delta, 0.0)
	if not is_networked() or not multiplayer.is_server():
		return
	LagComp.record(self)
	_ping_accum += delta
	if _ping_accum >= 0.45:
		_ping_accum = 0.0
		_sample_pings()
	if multiplayer.get_peers().is_empty():
		return
	var poses: Array = []
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or not p.is_bot:
			continue
		poses.append([p.peer_id, p.global_position, p.rotation.y, p.head.rotation.x, p.crouch, p.move_fx])
	if poses.is_empty():
		return
	sync_bot_poses.rpc(poses)


func _tick_regen(delta: float) -> void:
	Combat.tick_regen(self, delta)


@rpc("authority", "call_remote", "reliable", 1)
func sync_regen(batch: Array) -> void:
	if multiplayer.is_server():
		return
	for entry in batch:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 2:
			continue
		var p := player_for_peer(int(entry[0]))
		if p:
			p.apply_regen_hp(clampf(float(entry[1]), 0.0, Player.MAX_HP))


@rpc("authority", "call_remote", "unreliable", 2)
func sync_bot_poses(poses: Array) -> void:
	if multiplayer.is_server():
		return
	for entry in poses:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 4:
			continue
		var p := player_for_peer(int(entry[0]))
		if p and p.is_bot:
			p.apply_network_pose(entry[1], float(entry[2]), float(entry[3]), entry.slice(4, 6))


## Local human switched guns. Everyone needs the same def: sound, viewmodel, kill feed, server checks.
## By weapon id: slot numbers differ per class.
func announce_weapon(p: Player, weapon_id: StringName) -> void:
	if not is_networked() or p == null or p.is_bot:
		return
	if multiplayer.is_server():
		sync_weapon.rpc(p.peer_id, String(weapon_id))
	else:
		request_weapon_switch.rpc_id(1, String(weapon_id))


## Reliable and on the same channel as request_weapon_fire, so the server sees the switch before the shot.
## A gun outside the sender's class is refused (the server copy keeps the old one, so its shots fail too).
@rpc("any_peer", "call_remote", "reliable", 1)
func request_weapon_switch(weapon_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := player_for_peer(peer)
	if p == null or p.is_bot or p.weapon == null:
		return
	var id := StringName(weapon_id)
	if weapon_def(id) == null or not p.has_weapon(id):
		print("SERVER: refused switch to %s from %d (not in loadout)" % [weapon_id, peer])
		return
	p.weapon.equip_remote(id)
	sync_weapon.rpc(peer, weapon_id)


## #160: both flags and the capture score (authority → everyone, on every change and to late joiners).
@rpc("authority", "call_remote", "reliable", 0)
func sync_flags(packed: Array, caps_a: int, caps_b: int) -> void:
	if multiplayer.is_server():
		return
	_apply_flags(packed, caps_a, caps_b)


func _apply_flags(packed: Array, caps_a: int, caps_b: int) -> void:
	if flags.size() != 2:
		CTF.setup(self)
	for t in mini(packed.size(), 2):
		Objective.unpack(flags[t], packed[t])
	ctf_caps = [caps_a, caps_b]
	flags_changed.emit()


## #160: a flag event for the HUD/killfeed: kind is taken / dropped / returned / captured.
@rpc("authority", "call_remote", "reliable", 0)
func sync_flag_event(kind: String, team: int, peer: int) -> void:
	if multiplayer.is_server():
		return
	_apply_flag_event(kind, team, peer)


func _apply_flag_event(kind: String, team: int, peer: int) -> void:
	flag_event.emit(kind, team, _display_name_for(peer) if peer != 0 else "")


## #148: a peer's Gun Game step changed (authority → everyone).
@rpc("authority", "call_remote", "reliable", 0)
func sync_gun_level(peer_id: int, level: int) -> void:
	if multiplayer.is_server():
		return
	_apply_gun_level(peer_id, level)


## #148: mirror a step and arm the pawn with its gun (GunGame.arm decides who may).
func _apply_gun_level(peer_id: int, level: int) -> void:
	gun_level[peer_id] = level
	GunGame.arm(self, peer_id)
	if scores.has(peer_id):
		score_changed.emit(peer_id, int(scores[peer_id].kills), str(scores[peer_id].name))


@rpc("authority", "call_remote", "reliable", 1)
func sync_weapon(peer_id: int, weapon_id: String) -> void:
	if multiplayer.is_server():
		return
	var p := player_for_peer(peer_id)
	if p == null or p.is_local() or p.weapon == null:
		return
	p.weapon.equip_remote(StringName(weapon_id))


func live_peer_ids() -> Array:
	return MatchFlow.live_peer_ids(self)


func broadcast_roster() -> void:
	MatchFlow.broadcast_roster(self)


## Client deletes pawns the server no longer has (ghost bots after join-replace).
@rpc("authority", "call_remote", "reliable", 0)
func sync_roster(ids: Array) -> void:
	if multiplayer.is_server():
		return
	var valid := {}
	for id in ids:
		valid[int(id)] = true
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_local() or p.is_queued_for_deletion():
			continue
		if not valid.has(p.peer_id):
			p.queue_free()


func _ready() -> void:
	killcam = Killcam.new()
	killcam.name = "Killcam" # same path on every peer: its RPCs need that
	add_child(killcam)
	melee = Melee.new()
	melee.name = "Melee"
	add_child(melee)
	impacts = ImpactMarks.new()
	impacts.name = "ImpactMarks"
	add_child(impacts)
	loadouts = Loadouts.new()
	loadouts.name = "Loadouts"
	add_child(loadouts)
	freeze_grade = FreezeGrade.new()
	freeze_grade.name = "FreezeGrade"
	add_child(freeze_grade)
	speed_lines = SpeedLines.new()
	speed_lines.name = "SpeedLines"
	add_child(speed_lines)
	server_query = ServerQuery.new()
	server_query.name = "ServerQuery"
	add_child(server_query)
	_ensure_sfx_bus()
	load_settings()
	_bind_inputs()
	_round_music = AudioStreamPlayer.new()
	_round_music.bus = "Music"
	_round_music.stream = load("res://assets/sounds/round_start.wav")
	add_child(_round_music)
	_setup_tension_music()


func _ensure_sfx_bus() -> void:
	for bus_name in ["Music", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var b := AudioServer.bus_count
			AudioServer.add_bus()
			AudioServer.set_bus_name(b, bus_name)
			AudioServer.set_bus_send(b, "Master")
	if AudioServer.get_bus_index("SFX") != -1:
		_ensure_enemies_bus()
		return
	var i := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(i, "SFX")
	AudioServer.set_bus_send(i, "Master")
	# Ten guns at once: a soft compressor keeps the mix even, the limiter on Master stops clipping.
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 3.0
	comp.attack_us = 3000.0
	comp.release_ms = 140.0
	AudioServer.add_bus_effect(i, comp)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), limiter)
	_ensure_enemies_bus()


const SHADOW_NAMES := ["Auto (Graphics)", "Off", "Low", "Medium", "High"]
const CROSSHAIR_COLOR_NAMES := ["White", "Green", "Yellow", "Cyan", "Magenta", "Red"]
const CROSSHAIR_COLORS := [
	Color(0.95, 0.95, 0.95), Color(0.3, 1.0, 0.35), Color(1.0, 0.92, 0.25),
	Color(0.3, 0.95, 1.0), Color(1.0, 0.35, 0.95), Color(1.0, 0.3, 0.25),
]
const CROSSHAIR_STYLES := ["Cross + dot", "Cross", "Dot", "Circle"]
const COLORBLIND_NAMES := ["Off", "Red/green (blue vs yellow)", "Blue/yellow (teal vs red)"]
## Team A, team B per colourblind mode. Mode 0 is Player.TEAM_COLORS.
const COLORBLIND_TEAMS := [
	[Color(0.25, 0.55, 0.95), Color(0.92, 0.38, 0.22)],
	[Color(0.2, 0.45, 1.0), Color(1.0, 0.85, 0.1)],
	[Color(0.1, 0.8, 0.75), Color(0.95, 0.15, 0.3)],
]
## Rebindable gameplay actions, in menu order. toggle_mouse (Esc / pause) stays fixed.
const REBIND_ACTIONS := [
	["move_forward", "Forward"], ["move_back", "Back"], ["move_left", "Left"], ["move_right", "Right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["crouch", "Crouch / slide"],
	["fire", "Fire"], ["zoom", "Aim"], ["reload", "Reload"], ["switch_weapon", "Switch weapon"],
	["weapon_1", "Weapon 1"], ["weapon_2", "Weapon 2"], ["weapon_3", "Weapon 3"], ["weapon_4", "Weapon 4"],
	["melee", "Melee"], ["grenade", "Grenade"], ["throw_knife", "Throwing knife"],
	["use_streak", "Use streak"], ["chat", "Chat"],
]


func load_settings() -> void:
	GameSettings.load_settings(self)


func save_settings() -> void:
	GameSettings.save_settings(self)


## Profile name. Saves, tells the other name fields, and pushes a live pawn / lobby row when one exists.
## A trailing space is stripped here but the focused field keeps it until blur, so "Bob Smith" can be typed.
## `--name` must assign `player_name` directly so a one-off launch does not overwrite the file.
func set_player_name(n: String) -> void:
	var cleaned := clean_name(n)
	if cleaned == player_name:
		return
	player_name = cleaned
	profile_name = cleaned
	save_settings()
	_push_live_name()
	local_name_changed.emit(player_name)


## Scoreboard and lobby follow the profile name. Clients ask the server; the host writes it.
func _push_live_name() -> void:
	if not is_inside_tree() or is_dedicated:
		return
	var peer := 1
	if is_networked():
		peer = multiplayer.get_unique_id()
		if not multiplayer.is_server():
			var peer_obj := multiplayer.multiplayer_peer
			if peer_obj != null and peer_obj.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				submit_display_name.rpc_id(1, player_name)
				_retitle()
			return
	var n := unique_name(peer, player_name)
	if in_lobby:
		pending_names[peer] = n
		var team := preferred_team
		if lobby.has(peer):
			team = int(lobby[peer].get("team", team))
		set_lobby_member(peer, n, team)
		_retitle()
		return
	if player_for_peer(peer) != null or scores.has(peer):
		if is_networked():
			apply_display_name.rpc(peer, n)
		else:
			apply_display_name(peer, n)
		_retitle()


func _retitle() -> void:
	if display_headless():
		return
	DisplayServer.window_set_title("Gevechtspel — %s" % player_name)


func set_mouse_sens(v: float) -> void:
	mouse_sens = clampf(v, MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	save_settings()


func set_ads_sens(v: float) -> void:
	ads_sens = clampf(v, ADS_SENS_MIN, ADS_SENS_MAX)
	save_settings()


func set_invert_y(on: bool) -> void:
	invert_y = on
	save_settings()


## Menu choice for solo/host, remembered for next time.
func remember_match_choice(m: StringName, md: int, kills: int = -1, time_min: int = -1, bots: int = -1, skill: int = -1,
		allies: int = -1, enemies: int = -1) -> void:
	last_map = m
	if skill >= 0:
		last_bot_difficulty = clampi(skill, BOT_EASY, BOT_HARD)
		bot_difficulty = last_bot_difficulty
	last_mode = md
	if kills >= 0:
		last_kills = clampi(kills, KILLS_MIN, KILLS_MAX)
	if time_min >= 0:
		last_time_min = clampi(time_min, TIME_MIN_MINUTES, TIME_MAX_MINUTES)
	if allies >= 0 and enemies >= 0:
		last_bot_allies = clampi(allies, 0, BOT_COUNT_MAX)
		last_bot_enemies = clampi(enemies, 0, BOT_COUNT_MAX)
	if bots >= 0:
		last_bots = clampi(bots, 0, BOT_COUNT_MAX)
	save_settings()


func set_master_vol(v: float) -> void:
	master_vol = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()


func set_sfx_vol(v: float) -> void:
	sfx_vol = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()


func apply_audio() -> void:
	_set_bus_linear("Master", master_vol)
	_set_bus_linear("SFX", sfx_vol)
	_set_bus_linear("Enemies", enemies_vol)
	_set_bus_linear("Music", music_vol)
	_set_bus_linear("UI", ui_vol)


func set_music_vol(v: float) -> void:
	music_vol = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()


func set_ui_vol(v: float) -> void:
	ui_vol = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()


func set_shadow_quality(v: int) -> void:
	shadow_quality = clampi(v, 0, SHADOW_NAMES.size() - 1)
	apply_render()
	save_settings()


func set_crosshair(color_i: int, style_i: int, size_v: float) -> void:
	crosshair_color = clampi(color_i, 0, CROSSHAIR_COLORS.size() - 1)
	crosshair_style = clampi(style_i, 0, CROSSHAIR_STYLES.size() - 1)
	crosshair_size = clampf(size_v, 0.5, 2.0)
	save_settings()
	hud_settings_changed.emit()


func set_show_minimap(on: bool) -> void:
	show_minimap = on
	save_settings()
	hud_settings_changed.emit()


func set_show_killfeed(on: bool) -> void:
	show_killfeed = on
	save_settings()
	hud_settings_changed.emit()


## Repaints every pawn so the new palette shows at once.
func set_colorblind(v: int) -> void:
	colorblind = clampi(v, 0, COLORBLIND_NAMES.size() - 1)
	save_settings()
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("player"):
			if n.has_method("_apply_team_visual"):
				n._apply_team_visual()
	hud_settings_changed.emit()


func set_reduce_shake(on: bool) -> void:
	reduce_shake = on
	save_settings()


## Speed effects (FOV kick, speed lines, landing dip, wind). Local player only; no display-apply.
func set_speed_fx(on: bool) -> void:
	speed_fx = on
	save_settings()


## Camera shake and FOV punch multiplier. Recoil that moves the aim is not scaled.
func shake_scale() -> float:
	return 0.25 if reduce_shake else 1.0


func crosshair_rgb() -> Color:
	return CROSSHAIR_COLORS[crosshair_color]


func apply_shadows(map: Node) -> void:
	GameSettings.apply_shadows(self, map)


## True when the game has to restart to honour `choice`. Never for a dedicated server (systemd would
## restart it in a loop), never headless, never from the editor, and never twice: the relaunched
## process carries RENDERER_MARKER in its user args.
static func should_relaunch(choice: int, user_args: PackedStringArray, is_server: bool, headless: bool, editor: bool) -> bool:
	if choice <= 0 or choice >= RENDERER_IDS.size():
		return false
	if is_server or headless or editor:
		return false
	return not user_args.has(RENDERER_MARKER)


## Restarts the game with --rendering-method <method>, keeping every other user argument.
## False when the executable cannot be started (the caller then just keeps running).
func relaunch_with_renderer(method: String) -> bool:
	if method == "":
		return false
	var exe := OS.get_executable_path()
	if exe.is_empty() or not FileAccess.file_exists(exe):
		return false
	var argv := PackedStringArray(["--rendering-method", method, "--", RENDERER_MARKER])
	for a in OS.get_cmdline_user_args():
		if a != RENDERER_MARKER:
			argv.append(a)
	return OS.create_process(exe, argv) > 0


func set_renderer_choice(v: int) -> void:
	renderer_choice = clampi(v, 0, RENDERER_NAMES.size() - 1)
	save_settings()


func set_perf_overlay(v: int) -> void:
	perf_overlay = clampi(v, 0, PERF_NAMES.size() - 1)
	save_settings()
	if not is_inside_tree():
		return
	hud_settings_changed.emit()
	var label := get_tree().root.get_node_or_null("Main/CanvasLayer/Hud/Fps") as Label
	if label:
		label.visible = show_fps


func set_fov(v: float) -> void:
	fov = clampf(roundf(v), FOV_MIN, FOV_MAX)
	save_settings()
	_apply_fov_now()


## The live camera picks the new hip FOV immediately. ADS (absolute, ~38 for the sniper) is left alone.
## The menu camera has no ads_fov and is not a CameraFeel, so it stays on its own fov.
func _apply_fov_now() -> void:
	if not is_inside_tree() or display_headless():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var ads = cam.get("ads_fov")
	if ads == null or float(ads) > 1.0:
		return
	var extra = cam.get("extra_fov")
	cam.fov = fov + (float(extra) if extra != null else 0.0)


func set_window_mode(mode: int) -> void:
	window_mode = clampi(mode, WINDOW_WINDOWED, WINDOW_FULLSCREEN)
	apply_display()
	save_settings()


func set_resolution(size: Vector2i) -> void:
	window_size = size
	apply_display()
	save_settings()


func set_vsync(on: bool) -> void:
	vsync = on
	_apply_vsync_and_fps()
	save_settings()


func set_max_fps(v: int) -> void:
	max_fps = _snap_fps(v)
	_apply_vsync_and_fps()
	save_settings()


func set_render_scale(v: float) -> void:
	render_scale = _snap_scale(v)
	apply_render()
	save_settings()


func set_view_sway(v: int) -> void:
	view_sway = clampi(v, 0, 2)
	save_settings()


func set_gfx_quality(v: int) -> void:
	gfx_quality = clampi(v, 0, 2)
	apply_render()
	save_settings()


func set_msaa(v: int) -> void:
	msaa = clampi(v, 0, 3)
	apply_render()
	save_settings()


## True for `./run.sh --headless` and the dedicated server. Video settings must not touch the window.
func display_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func resolution_choices() -> Array:
	return GameSettings.resolution_choices(self)


func _resolutions_fitting(screen: Vector2i) -> Array:
	return GameSettings.resolutions_fitting(self, screen)


func apply_display() -> void:
	GameSettings.apply_display(self)


func _apply_vsync_and_fps() -> void:
	GameSettings.apply_vsync_and_fps(self)


func _apply_window() -> void:
	GameSettings.apply_window(self)


func _clamp_window_size(size: Vector2i, screen: Vector2i) -> Vector2i:
	return GameSettings.clamp_window_size(self, size, screen)


func apply_render() -> void:
	GameSettings.apply_render(self)


func _snap_fps(v: int) -> int:
	return GameSettings.snap_fps(self, v)


func _snap_scale(v: float) -> float:
	return GameSettings.snap_scale(self, v)


func _ensure_enemies_bus() -> void:
	if AudioServer.get_bus_index("Enemies") != -1:
		return
	var b := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(b, "Enemies")
	AudioServer.set_bus_send(b, "SFX")


func set_enemies_vol(v: float) -> void:
	enemies_vol = clampf(v, 0.0, ENEMIES_VOL_MAX)
	_set_bus_linear("Enemies", enemies_vol)
	save_settings()


func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	if linear <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _bind_inputs() -> void:
	Keybinds.bind_inputs(self)


func _event_code(ev: InputEvent) -> String:
	return Keybinds.event_code(self, ev)


func _event_from_code(code: String) -> InputEvent:
	return Keybinds.event_from_code(self, code)


func binding_text(action: String) -> String:
	return Keybinds.binding_text(self, action)


func rebind(action: String, ev: InputEvent) -> String:
	return Keybinds.rebind(self, action, ev)


func _first_code(action: String) -> String:
	return Keybinds.first_code(self, action)


func reset_bindings() -> void:
	Keybinds.reset_bindings(self)


func _key(action: String, keycode: Key) -> void:
	Keybinds.key(self, action, keycode)


func _mouse(action: String, button: MouseButton) -> void:
	Keybinds.mouse(self, action, button)


func _has_key(action: String, keycode: Key) -> bool:
	return Keybinds.has_key(self, action, keycode)


func _has_mouse(action: String, button: MouseButton) -> bool:
	return Keybinds.has_mouse(self, action, button)


## Engine.time_scale is global: on a listen server it would slow bots, timers, and physics for everyone.
func hitstop(seconds: float = 0.05, scale: float = 0.22) -> void:
	if _hitstopping or (is_networked() and multiplayer.is_server()):
		return
	_hitstopping = true
	Engine.time_scale = scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstopping = false


## A successful connect puts "ip:port" on top of the recent list (deduped, capped) and saves.
func remember_server(ip: String, port: int) -> void:
	var key := "%s:%d" % [ip.strip_edges(), port]
	var out := PackedStringArray([key])
	for e in recent_servers:
		if e != key and out.size() < RECENT_SERVERS_MAX:
			out.append(e)
	recent_servers = out
	last_server = key
	save_settings()


func set_last_server(key: String) -> void:
	last_server = key.strip_edges()
	save_settings()


## "label|host:port" entries; label may be empty. Same address twice is ignored.
func add_favorite(label: String, address: String) -> bool:
	address = address.strip_edges()
	if address.is_empty():
		return false
	for e in favorite_servers:
		if e.get_slice("|", 1) == address or e == address:
			return false
	favorite_servers.append("%s|%s" % [label.strip_edges(), address])
	save_settings()
	return true


func remove_favorite(address: String) -> void:
	var out := PackedStringArray()
	for e in favorite_servers:
		if e.get_slice("|", 1) != address and e != address:
			out.append(e)
	favorite_servers = out
	save_settings()


## Every frame, not per physics tick: the menu fade must not wait for the first physics step (#62).
func _process(_delta: float) -> void:
	_tick_menu_music()


## Quit while a loop plays: stop it so the stream is not leaked at exit.
func _exit_tree() -> void:
	for pl in [_menu_music, _tension, _round_music]:
		if pl:
			pl.stop()
			pl.stream = null
