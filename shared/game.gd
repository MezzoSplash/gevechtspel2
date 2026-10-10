extends Node
## Autoload `Game`. Shared weapon stats, server-authoritative hits, scores, and LAN RPCs.
## Clients never decide damage, deaths, or bot actions.

signal hit_confirmed(killed: bool, headshot: bool)
signal local_player_ready(player: Player)
signal score_changed(peer_id: int, score: int, name: String)
signal round_ended(winner_peer_id: int, winner_name: String, scores: Dictionary)
## `tricks`: "" or the trickshot label for the feed tag ("360 NOSCOPE + AIRSHOT").
signal kill_feed(killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int, tricks: String)
## Every machine: a kill was a trickshot. `tricks` is Style.pack form; `total` the killer's style this round.
signal trick_scored(killer_peer_id: int, tricks: String, points: int, multiplier: float, total: int)
signal presence(player_name: String, joined: bool, team: int)
signal chat_message(player_name: String, team: int, text: String)
signal lobby_changed
signal match_starting
signal round_freeze_changed(frozen: bool)
signal intermission_started
## Fired when the saved profile name changes, so the menu fields stay in sync.
signal local_name_changed(n: String)

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
const MODE_IDS := ["tdm", "ffa"]
const MODE_NAMES := ["Team Deathmatch", "Free For All"]
const FFA_WIN_KILLS := 20
const KILLS_MIN := 5
const KILLS_MAX := 50
const TIME_MIN_MINUTES := 1
const TIME_MAX_MINUTES := 20
const BOT_COUNT_DEFAULT := 9
const BOT_COUNT_MAX := 16
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
## 0.3.3 is the Quay mesh cleanup (solid landings, no floating corner wall). 0.3.2 and older cannot join.
const NET_VERSION := "0.3.3"
const REGEN_SYNC := 0.25 # seconds between sync_regen batches
## Server-side shot checks. Lenient on purpose: LAN jitter must never eat a legit shot.
const FIRE_RATE_SLACK := 1.15 # shot credit refills 15% faster than the gun fires
const FIRE_ORIGIN_TOLERANCE := 4.0 # metres between the client's eye and our copy of it
const SPREAD_MAX := 8.0 # slide spread; clients cannot ask for more (or less than standing)
const WEAPON_DEFS := {
	&"rifle": preload("res://data/weapons/rifle.tres"),
	&"pistol": preload("res://data/weapons/pistol.tres"),
	&"shotgun": preload("res://data/weapons/shotgun.tres"),
	&"sniper": preload("res://data/weapons/sniper.tres"),
	&"smg": preload("res://data/weapons/smg.tres"),
	&"revolver": preload("res://data/weapons/revolver.tres"),
}

var is_offline := true
var is_dedicated := false
var chat_open := false # T-chat: blocks move/look/fire until Enter/Esc
var pause_open := false
var in_lobby := false
var round_frozen := false # look OK, no walk/shoot; bots idle
var killcam_active := false # final killcam: no walk/look/shoot/damage; bots idle (Killcam.sync_lock)
var rc_view := false # this machine is looking out of an RC-XD; the pawn stays put and cannot shoot
var final_kill: Dictionary = {} # match authority: last real kill of this round, replayed by the killcam
var best_trick: Dictionary = {} # match authority: this round's highest-scoring trickshot (same keys + tags/pts/trick_id)
var _shot_ctx: Dictionary = {} # match authority, while a shot resolves: {shooter, origin, scoped}
var _style_chain: Dictionary = {} # peer_id -> [trick kills in a row, time of the last one]
var _line_cd: Dictionary = {} # peer_id -> {strip name: seconds left}. Points only; the shove is local.
var _line_chain: Dictionary = {} # peer_id -> [last strip name, seconds left in the carry window]
var _line_pos: Dictionary = {} # peer_id -> last physics position (speed is the delta, not _obs_speed)
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
var mouse_sens := 1.0 # multiplier on Player.MOUSE_SENS (settings)
var ads_sens := 0.45 # extra multiplier while aiming down sights / scoped
var last_map: StringName = Maps.DEFAULT # menu's last pick (settings.cfg [match])
var last_mode := MODE_TDM
var last_kills := WIN_KILLS
var last_time_min := 10
var last_bots := BOT_COUNT_DEFAULT
var kill_limit := WIN_KILLS # this match: TDM team total, FFA personal
var round_time := ROUND_TIME # this match, seconds
var bot_count := BOT_COUNT_DEFAULT # this match: how many bot pawns to keep
## main.gd: Callable(Player) -> Transform3D. Every respawn asks it (FFA: spot farthest from enemies).
var spawn_picker: Callable
## main.gd: Callable(map_id, mode) -> void. Clients load the server's map before their pawn spawns.
var match_config_handler: Callable
var lobby: Dictionary = {} # peer_id → {name, team}
var master_vol := 1.0
var sfx_vol := 1.0
var player_name := "Player" # this launch. --name replaces it and must not be written back.
var profile_name := "Player" # the name settings.cfg keeps across launches
var window_mode := WINDOW_WINDOWED
var window_size := Vector2i(1600, 900) # project.godot's window override; the first-run default
var vsync := true
var max_fps := 0 # 0 = no Engine cap. VSync, when on, still follows the monitor.
var fov := 90.0 # hip fire. Weapon ADS fov stays absolute so a scope does not scale with this.
var render_scale := 1.0 # 3D buffer only (Viewport.scaling_3d_scale). HUD stays at the window size.
var msaa := 2 # Viewport.MSAA: 0 off, 1 = 2x, 2 = 4x, 3 = 8x. Matches project.godot msaa_3d=2 (4x).
var show_fps := true
var invert_y := false
var preferred_team := 0 # 0 Blue, 1 Orange — chosen in the menu
var pending_names: Dictionary = {} # peer_id → name, filled before spawn if the client RPCs first
var pending_teams: Dictionary = {} # peer_id → team, from join RPC
var net_hp: Dictionary = {} # server copy of HP, keyed by peer_id (bots included)
var _regen_dirty: Dictionary = {} # peer_id -> hp changed by regen since the last sync_regen
var _regen_sync_t := 0.0
var _hitstopping := false
var _round_music: AudioStreamPlayer
var _grenade_seq := 0
var _grenade_visuals: Dictionary = {}
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


func rpc_from_server() -> bool:
	if is_offline:
		return true
	var id := multiplayer.get_remote_sender_id()
	return id == 1 or id == 0


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


func is_ffa() -> bool:
	return mode == MODE_FFA


func mode_name(m: int = -1) -> String:
	return MODE_NAMES[clampi(mode if m < 0 else m, 0, MODE_NAMES.size() - 1)]


## "ffa", "FFA", "free" or "2" → MODE_FFA. Unknown → -1.
static func parse_mode(raw: String) -> int:
	var s := raw.strip_edges().to_lower()
	if s in ["tdm", "team", "teams", "team_deathmatch", "1"]:
		return MODE_TDM
	if s in ["ffa", "free", "freeforall", "free_for_all", "dm", "2"]:
		return MODE_FFA
	return -1


func win_kills() -> int:
	return kill_limit


func default_kills_for(m: int = -1) -> int:
	return FFA_WIN_KILLS if (mode if m < 0 else m) == MODE_FFA else WIN_KILLS


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
@rpc("authority", "reliable")
func sync_match_config(new_map: String, new_mode: int, kills: int = 0, time_sec: float = 0.0) -> void:
	if multiplayer.is_server():
		return
	set_match_config(StringName(new_map), new_mode, kills, time_sec)


func set_match_config(new_map: StringName, new_mode: int, kills: int = -1, time_sec: float = -1.0, bots: int = -1) -> void:
	map_id = new_map if Maps.has(new_map) else Maps.DEFAULT
	mode = clampi(new_mode, MODE_TDM, MODE_FFA)
	kill_limit = clampi(kills if kills >= KILLS_MIN else last_kills, KILLS_MIN, KILLS_MAX)
	round_time = time_sec if time_sec >= 60.0 else float(last_time_min * 60)
	round_time = clampf(round_time, float(TIME_MIN_MINUTES * 60), float(TIME_MAX_MINUTES * 60))
	bot_count = clampi(bots if bots >= 0 else last_bots, 0, BOT_COUNT_MAX)
	if match_config_handler.is_valid():
		match_config_handler.call(map_id, mode)


## Team of this machine's own pawn, -1 when there is none (menu, dedicated server).
func local_team() -> int:
	var me := player_for_peer(multiplayer.get_unique_id())
	return me.team_id if me else -1


func hp_of(p: Player) -> float:
	if not is_networked():
		return p.hp
	var id := p.peer_id
	if id == 0:
		id = p._owner_peer()
	if not net_hp.has(id):
		net_hp[id] = Player.MAX_HP
	return float(net_hp[id])


func set_hp(p: Player, value: float) -> void:
	p.hp = value
	if is_networked() and p.peer_id != 0:
		net_hp[p.peer_id] = value


## Forget a peer that left: HP, name/team, streak, ping, shot credit, and its scoreboard row (synced).
func clear_peer_hp(peer_id: int) -> void:
	net_hp.erase(peer_id)
	pending_names.erase(peer_id)
	pending_teams.erase(peer_id)
	streak_progress.erase(peer_id)
	streak_charges.erase(peer_id)
	streak_earned.erase(peer_id)
	RcXd.abort_for(peer_id)
	pings.erase(peer_id)
	_fire_credit.erase(peer_id)
	if melee:
		melee.forget(peer_id)
	if loadouts:
		loadouts.forget(peer_id)
	drop_score(peer_id)


## Removes a scoreboard row on every machine. Team totals live in team_kills and stay.
func drop_score(peer_id: int) -> void:
	scores.erase(peer_id)
	if is_networked() and multiplayer.is_server():
		sync_score_removed.rpc(peer_id)


@rpc("authority", "reliable")
func sync_score_removed(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	scores.erase(peer_id)
	pings.erase(peer_id)


## Trimmed to NAME_MAX, one line. Used for every name that reaches the scoreboard.
func clean_name(n: String, fallback: String = "Player") -> String:
	n = n.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if n.length() > NAME_MAX:
		n = n.substr(0, NAME_MAX).strip_edges()
	return n if n != "" else fallback


func weapon_def(weapon_id: StringName) -> WeaponDef:
	return WEAPON_DEFS.get(weapon_id) as WeaponDef


## Client → server fire. Hits resolve here; tracers/sfx go back out via broadcast_shot_fx.
## The server checks: equipped gun, fire rate, freeze, and that the shot starts near our copy of the shooter.
## `shot_seed` makes the server's pellets the same as the client's tracers.
@rpc("any_peer", "reliable")
func request_weapon_fire(
	origin: Vector3,
	look_dir: Vector3,
	weapon_id: StringName,
	muzzle_pos: Vector3 = Vector3.ZERO,
	spread_mult: float = 1.0,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0,
	mag: int = 0
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
	var best := _resolve_weapon_fire(shooter, origin, look_dir, def, mult, shot_seed, scoped, burst, mag)
	var from := muzzle_pos
	if from == Vector3.ZERO or from.distance_to(origin) > 2.0:
		from = origin
	broadcast_shot_fx(from, best.get("end", origin + look_dir.normalized() * def.range_m), peer)
	if best.get("hit", false):
		notify_hit.rpc_id(peer, best.killed, best.headshot)


## Client eye vs. our copy of it. Position is client-synced, so this only stops "shoot from anywhere".
func origin_plausible(shooter: Player, origin: Vector3) -> bool:
	var eye := shooter.camera.global_position if shooter.camera else shooter.global_position
	return eye.distance_to(origin) <= FIRE_ORIGIN_TOLERANCE


## Per gun: credit refills a bit faster than the fire rate and holds ~1.5 shots, so packet bunching passes
## but a fast-fire hack does not. Per gun because a switch does not reset the client's cooldown either.
func _take_fire_credit(peer: int, def: WeaponDef) -> bool:
	var interval := 1.0 / maxf(def.fire_rate, 0.01)
	var cap := interval * 1.5 + 0.1
	var now := Time.get_ticks_msec() / 1000.0
	if not _fire_credit.has(peer):
		_fire_credit[peer] = {}
	var per_gun: Dictionary = _fire_credit[peer]
	var state: Array = per_gun.get(def.id, [cap, now])
	var credit := minf(float(state[0]) + (now - float(state[1])) * FIRE_RATE_SLACK, cap)
	if credit < interval * 0.85:
		per_gun[def.id] = [credit, now]
		return false
	per_gun[def.id] = [credit - interval, now]
	return true


func next_grenade_id() -> int:
	_grenade_seq += 1
	return _grenade_seq


## Authority only. Clients ask via request_grenade; the count RPC updates their HUD.
func throw_grenade(thrower: Player, origin: Vector3, dir: Vector3) -> void:
	if thrower == null or thrower.is_dead or thrower.grenades <= 0 or play_locked():
		return
	if is_networked() and not multiplayer.is_server():
		return
	thrower.grenades -= 1
	thrower._notify_grenades()
	if is_networked():
		sync_grenade_count.rpc(thrower.peer_id, thrower.grenades)
	Grenade.launch(thrower, origin, dir)


## Client throw. Server re-checks ammo, death, and freeze.
@rpc("any_peer", "reliable")
func request_grenade(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var thrower := player_for_peer(peer)
	if thrower == null or dir.length_squared() < 0.0001 or not origin_plausible(thrower, origin):
		return
	throw_grenade(thrower, origin, dir)


@rpc("authority", "call_local", "reliable")
func sync_grenade_count(peer_id: int, n: int) -> void:
	var p := player_for_peer(peer_id)
	if p == null:
		return
	p.grenades = n
	p._notify_grenades()


## Visual copy on clients. Physics stays on the server grenade.
@rpc("authority", "reliable")
func sync_grenade_spawn(net_id: int, pos: Vector3) -> void:
	if multiplayer.is_server() or _grenade_done.has(net_id):
		return
	_grenade_visual(net_id, pos)


@rpc("authority", "unreliable")
func sync_grenade_pose(net_id: int, pos: Vector3) -> void:
	# Unreliable can arrive after the reliable boom; that would leave a ghost grenade.
	if multiplayer.is_server() or _grenade_done.has(net_id):
		return
	var g := _grenade_visual(net_id, pos)
	if g:
		g.global_position = pos


## Drop the flying mesh, then play the same boom the server already showed.
@rpc("authority", "reliable")
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


func _grenade_visual(net_id: int, pos: Vector3) -> Node3D:
	if _grenade_visuals.has(net_id) and is_instance_valid(_grenade_visuals[net_id]):
		return _grenade_visuals[net_id]
	var g := Grenade.new()
	var scene := get_tree().current_scene
	if scene == null:
		return null
	scene.add_child(g)
	g.global_position = pos
	_grenade_visuals[net_id] = g
	return g


# --- Throwing knives (grenade slot, F). Same flow as grenades: authority decides, clients get copies. ---

## Authority only. Clients ask via request_knife.
func throw_knife(thrower: Player, origin: Vector3, dir: Vector3) -> void:
	if thrower == null or thrower.is_dead or thrower.knives <= 0 or play_locked():
		return
	if is_networked() and not multiplayer.is_server():
		return
	thrower.knives -= 1
	thrower._notify_grenades()
	if is_networked():
		sync_knife_count.rpc(thrower.peer_id, thrower.knives)
	ThrowingKnife.launch(thrower, origin, dir)


@rpc("any_peer", "reliable")
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


@rpc("authority", "call_local", "reliable")
func sync_knife_count(peer_id: int, n: int) -> void:
	var p := player_for_peer(peer_id)
	if p == null:
		return
	p.knives = n
	p._notify_grenades()


## Clients fly a visual copy from the release; sync_knife_done ends it where the server says.
@rpc("authority", "reliable")
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
@rpc("authority", "reliable")
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


## Server knife hit a body: one-hit kill, the throw is the "shot" for tricks (YEET).
func knife_hit(knife: ThrowingKnife, victim: Player, point: Vector3, normal: Vector3) -> void:
	var thrower := player_for_peer(knife.thrower_id)
	if thrower:
		_shot_ctx = {"shooter": thrower, "origin": knife.origin, "scoped": false, "burst": {}, "knife_air": knife.airborne}
	var killer_id := knife.thrower_id
	if killer_id <= 0 and thrower:
		killer_id = thrower._owner_peer()
	var res := victim.apply_hit(point, normal, ThrowingKnife.DAMAGE, false, killer_id, &"knife", 1.0, knife.origin)
	_shot_ctx = {}
	if res.get("damage", 0) <= 0 or thrower == null:
		return
	if thrower.is_local():
		hit_confirmed.emit(bool(res.killed), false)
		if thrower.weapon:
			thrower.weapon.play_hit_feedback(bool(res.killed), false)
	elif is_networked() and not thrower.is_bot and thrower.peer_id > 0:
		notify_hit.rpc_id(thrower.peer_id, bool(res.killed), false)


## Host / offline / bots: resolve hits on this machine (must be match authority).
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
	return _resolve_weapon_fire(shooter, origin, look_dir, def, spread_mult, shot_seed, scoped, burst, mag)


## `shot_seed` drives the pellet spread, so Weapon._simulate_pellets_fx draws the same rays.
## Teammates are excluded: shots pass through friends instead of being soaked up by them.
## `scoped`: the shooter had the sniper scope up (only matters for the NOSCOPE trick, never for damage).
## `burst`: the shooter's held-trigger counter for automatic guns (SPRAY TRANSFER only; 0 = unknown).
## `mag`: the shooter's magazine counter for this gun (Weapon.mag_seq; HOSE / SIX SHOOTER only).
func _resolve_weapon_fire(
	shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0,
	mag: int = 0
) -> Dictionary:
	_shot_ctx = {
		"shooter": shooter, "origin": origin, "scoped": scoped, "burst": _burst_for(shooter, def, burst),
		"mag": _mag_for(shooter, def, mag),
	}
	var best := _resolve_shot_rays(shooter, origin, look_dir, def, spread_mult, shot_seed)
	_shot_ctx = {}
	return best


func _resolve_shot_rays(
	shooter: Player, origin: Vector3, look_dir: Vector3, def: WeaponDef, spread_mult: float, shot_seed: int
) -> Dictionary:
	look_dir = look_dir.normalized()
	var spread := def.spread_deg * spread_mult
	var best := {"killed": false, "headshot": false, "hit": false, "end": origin + look_dir * def.range_m}
	var space := shooter.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = shot_seed if shot_seed != 0 else randi()
	var exclude := shot_exclude(shooter)
	for i in def.pellet_count:
		var dir := spread_dir(look_dir, spread, rng)
		var to := origin + dir * def.range_m
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.collision_mask = SHOT_MASK
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if i == 0:
			best.end = to if hit.is_empty() else hit.position
		if hit.is_empty():
			continue
		var dist := origin.distance_to(hit.position)
		var dmg := def.damage_at_distance(dist)
		var result := _apply_shot_hit(shooter, hit, dmg, def)
		if result.is_empty():
			continue
		var end: Vector3 = best.end
		best = _merge_hit_result(best, result)
		best.end = end
	return best


## The rifle burst this shot belongs to: same trigger hold (client counter) and no pause over
## Style.BURST_GAP. Kills append their victim (register_kill). {} for other guns.
func _burst_for(shooter: Player, def: WeaponDef, seq: int) -> Dictionary:
	if not def.automatic or seq == 0:
		return {}
	var now := Time.get_ticks_msec() / 1000.0
	var b: Dictionary = _bursts.get(shooter.peer_id, {})
	if b.is_empty() or int(b.seq) != seq or now - float(b.t) > Style.BURST_GAP:
		b = {"seq": seq, "t": now, "victims": []}
		_bursts[shooter.peer_id] = b
	b.t = now
	return b


## The magazine this shot comes from: same client counter and no more shots than the gun holds
## (a client that never bumps its counter still gets a fresh magazine every mag_size shots).
## Kills add to it (register_kill). Every gun is tracked; only the SMG and revolver tricks read it.
func _mag_for(shooter: Player, def: WeaponDef, seq: int) -> Dictionary:
	var per: Dictionary = _mags.get(shooter.peer_id, {})
	_mags[shooter.peer_id] = per
	var m: Dictionary = per.get(def.id, {})
	if m.is_empty() or int(m.seq) != seq or int(m.shots) >= def.mag_size:
		m = {"seq": seq, "shots": 0, "kills": 0, "weapon": def.id}
		per[def.id] = m
	m.shots = int(m.shots) + 1
	return m


## Melee: the swing is the "shot" for the movement tricks (SURF / DROP KILL).
func begin_melee_ctx(attacker: Player, origin: Vector3) -> void:
	_shot_ctx = {"shooter": attacker, "origin": origin, "scoped": false, "burst": {}}


func end_melee_ctx() -> void:
	_shot_ctx = {}


## Shooter plus living teammates (none in FFA). Used for shots, tracers, and bot line of sight.
func shot_exclude(shooter: Player) -> Array[RID]:
	var out: Array[RID] = [shooter.get_rid()]
	if is_ffa():
		return out
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and p != shooter and p.team_id == shooter.team_id and not p.is_dead:
			out.append(p.get_rid())
	return out


func _merge_hit_result(best: Dictionary, result: Dictionary) -> Dictionary:
	if result.get("killed", false):
		return {"killed": true, "headshot": result.headshot, "hit": true}
	if best.killed:
		return best
	if result.get("headshot", false):
		return {"killed": false, "headshot": true, "hit": true}
	if best.headshot:
		return best
	return {"killed": false, "headshot": false, "hit": true}


## Shared by server hits and client tracers. Same rng seed → same pellets.
func spread_dir(forward: Vector3, deg: float, rng: RandomNumberGenerator) -> Vector3:
	if deg <= 0.0:
		return forward.normalized()
	var rad := deg_to_rad(deg)
	var theta := rng.randf() * TAU
	var phi := rad * sqrt(rng.randf())
	var up := Vector3.UP
	var right := forward.cross(up)
	if right.length_squared() < 0.001:
		right = forward.cross(Vector3.RIGHT)
	right = right.normalized()
	up = right.cross(forward).normalized()
	return (forward.normalized() * cos(phi) + (right * cos(theta) + up * sin(theta)) * sin(phi)).normalized()


func _apply_shot_hit(shooter: Player, hit: Dictionary, damage: float, def: WeaponDef) -> Dictionary:
	var collider := hit.collider as Node
	if collider == null:
		return {}
	var killer_id := shooter.peer_id
	if killer_id <= 0:
		killer_id = shooter._owner_peer()
	if collider is Player:
		var victim := collider as Player
		if victim == shooter or victim.is_dead:
			return {}
		if not is_enemy(victim, shooter):
			return {}
		return victim.apply_hit(
			hit.position, hit.normal, damage, true, killer_id, def.id, def.headshot_multiplier, shooter.global_position
		)
	# RC-XD sits on layer 4 (inside SHOT_MASK). Destroying it does not splash.
	var rc := collider as RcXd
	if rc:
		rc.damage(damage)
		return {"killed": false, "headshot": false, "hit": true}
	return {}


@rpc("authority", "reliable")
func notify_hit(killed: bool, headshot: bool) -> void:
	hit_confirmed.emit(killed, headshot)


@rpc("any_peer", "reliable")
func submit_display_name(n: String, team: int = -1) -> void:
	if not multiplayer.is_server():
		return
	n = clean_name(n)
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
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
@rpc("authority", "call_local", "reliable")
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
@rpc("authority", "call_local", "reliable")
func broadcast_hurt(peer_id: int, new_hp: float, killed: bool, from_pos: Vector3 = Vector3.INF) -> void:
	var p := player_for_peer(peer_id)
	if p:
		p.apply_hurt_state(new_hp, killed, from_pos)


## Authority: every respawn (death timer, round start) goes through here so a waiting class
## change reaches the owner before the respawn does, and everyone sees the primary in hand.
func respawn_pawn(p: Player) -> void:
	if p == null:
		return
	set_hp(p, Player.MAX_HP)
	if loadouts:
		loadouts.promote_pending(p)
	var xf := p._spawn_xform
	if spawn_picker.is_valid():
		xf = spawn_picker.call(p)
	if is_networked():
		broadcast_respawn.rpc(p.peer_id, xf)
		if not p.is_bot and not p.loadout.is_empty():
			sync_weapon.rpc(p.peer_id, String(p.loadout.primary))
	else:
		p._spawn_xform = xf
		p.apply_respawn_state()


## `xform`: the spawn point the server picked (FFA picks a new one every time).
@rpc("authority", "call_local", "reliable")
func broadcast_respawn(peer_id: int, xform: Transform3D) -> void:
	var p := player_for_peer(peer_id)
	if p:
		p._spawn_xform = xform
		p.apply_respawn_state()


func take_pending_name(peer_id: int, fallback: String) -> String:
	if pending_names.has(peer_id):
		var n: String = pending_names[peer_id]
		pending_names.erase(peer_id)
		return n
	return fallback


func _is_match_authority() -> bool:
	return not is_networked() or multiplayer.is_server()


func _display_name_for(peer_id: int) -> String:
	var killer := player_for_peer(peer_id)
	if killer:
		return killer.display_name
	if peer_id < 0:
		return "Bot %d" % abs(peer_id)
	return "Player"


func _apply_score(peer_id: int, kills: int, n: String, team: int = 0) -> void:
	if not scores.has(peer_id):
		scores[peer_id] = {"name": n, "kills": 0, "team": team, "style": 0}
	scores[peer_id].kills = kills
	scores[peer_id].name = n
	scores[peer_id].team = team
	score_changed.emit(peer_id, kills, n)


## Called when a pawn spawns (and for a killer without a row). `team` is the pawn's, so it always
## wins over a row made earlier by apply_display_name, and the fix is synced to everyone.
func register_participant(peer_id: int, n: String, team: int = 0) -> void:
	if scores.has(peer_id):
		var existing: String = str(scores[peer_id].name)
		var incoming_placeholder := n == "" or n == "Player"
		var keep_existing := existing != "" and existing != "Player"
		var new_name := existing if n == "" or (incoming_placeholder and keep_existing) else n
		if new_name == existing and int(scores[peer_id].get("team", -1)) == team:
			return
		_apply_score(peer_id, int(scores[peer_id].kills), new_name, team)
		if is_networked() and multiplayer.is_server():
			sync_score.rpc(peer_id, int(scores[peer_id].kills), new_name, team)
		return
	_apply_score(peer_id, 0, n, team)
	if is_networked() and multiplayer.is_server():
		sync_score.rpc(peer_id, 0, n, team)


const CHAT_MAX := 120


## All-chat. Clients send to the server; host stamps name/team and broadcasts.
func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text.length() > CHAT_MAX:
		text = text.substr(0, CHAT_MAX)
	if text == "":
		return
	if not is_networked():
		_deliver_chat(player_name, _local_team(), text)
		return
	if multiplayer.is_server():
		_relay_chat(multiplayer.get_unique_id(), text)
	else:
		submit_chat.rpc_id(1, text)


func _local_team() -> int:
	var p := player_for_peer(multiplayer.get_unique_id() if is_networked() else 1)
	return p.team_id if p else 0


## Never trust the client for the display name — look up the pawn / scoreboard.
func _relay_chat(peer_id: int, text: String) -> void:
	var p := player_for_peer(peer_id)
	var n := _display_name_for(peer_id)
	var team := 0
	if p:
		n = p.display_name
		team = p.team_id
	elif scores.has(peer_id):
		n = str(scores[peer_id].name)
		team = int(scores[peer_id].get("team", 0))
	broadcast_chat.rpc(n, team, text)


## Client → server. Strip/cap here again in case of a bad peer.
@rpc("any_peer", "reliable")
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
@rpc("authority", "call_local", "reliable")
func broadcast_chat(n: String, team: int, text: String) -> void:
	_deliver_chat(n, team, text)


func _deliver_chat(n: String, team: int, text: String) -> void:
	chat_message.emit(n, team, text)


func set_lobby_member(peer_id: int, n: String, team: int) -> void:
	if not _is_match_authority():
		return
	lobby[peer_id] = {"name": n, "team": clampi(team, TEAM_A, TEAM_B)}
	_push_lobby()


func remove_lobby_member(peer_id: int) -> void:
	if not lobby.has(peer_id):
		return
	lobby.erase(peer_id)
	if _is_match_authority():
		_push_lobby()


func _push_lobby() -> void:
	lobby_changed.emit()
	if is_networked() and multiplayer.is_server():
		sync_lobby.rpc(lobby)


@rpc("authority", "reliable")
func sync_lobby(data: Dictionary) -> void:
	if multiplayer.is_server():
		return
	lobby = data
	lobby_changed.emit()


@rpc("any_peer", "reliable")
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


@rpc("authority", "call_local", "reliable")
func begin_match() -> void:
	in_lobby = false
	match_starting.emit()


func announce_presence(player_name: String, joined: bool, team: int) -> void:
	if not _is_match_authority():
		return
	presence.emit(player_name, joined, team)
	if is_networked():
		sync_presence.rpc(player_name, joined, team)


@rpc("authority", "reliable")
func sync_presence(player_name: String, joined: bool, team: int) -> void:
	if multiplayer.is_server():
		return
	presence.emit(player_name, joined, team)


## Server/offline only. Updates TDM score and kill feed (weapon_id is the gun used).
## Also remembers the kill as this round's final kill until a later one replaces it.
func register_kill(
	killer_peer_id: int, victim_peer_id: int, weapon_id: StringName = &"rifle", headshot: bool = false
) -> void:
	if not _is_match_authority():
		return
	if killer_peer_id == 0:
		return
	if killer_peer_id == victim_peer_id:
		_register_suicide(victim_peer_id, weapon_id)
		return
	if not scores.has(killer_peer_id):
		var killer := player_for_peer(killer_peer_id)
		var team := killer.team_id if killer else 0
		register_participant(killer_peer_id, _display_name_for(killer_peer_id), team)
	var kills: int = int(scores[killer_peer_id].kills) + 1
	var n: String = scores[killer_peer_id].name
	var team_id: int = int(scores[killer_peer_id].get("team", 0))
	var killer_pawn := player_for_peer(killer_peer_id)
	if killer_pawn:
		team_id = killer_pawn.team_id # the pawn is the truth; a stale row must not credit the other team
	_apply_score(killer_peer_id, kills, n, team_id)
	if is_networked():
		sync_score.rpc(killer_peer_id, kills, n, team_id)
	_add_team_kill(team_id)
	var killer_name := n
	var victim_name := _display_name_for(victim_peer_id)
	if scores.has(victim_peer_id):
		victim_name = str(scores[victim_peer_id].name)
	var victim_team := 0
	var victim := player_for_peer(victim_peer_id)
	if victim:
		victim_team = victim.team_id
	elif scores.has(victim_peer_id):
		victim_team = int(scores[victim_peer_id].get("team", 0))
	var tricks := _detect_tricks(killer_peer_id, victim_peer_id, weapon_id, headshot)
	_note_trick_history(killer_peer_id, victim_peer_id, weapon_id, headshot)
	var tag := Style.label(tricks)
	_emit_kill_feed(killer_name, victim_name, weapon_id, team_id, victim_team, tag)
	if is_networked():
		sync_kill_feed.rpc(killer_name, victim_name, String(weapon_id), team_id, victim_team, tag)
	var kill_info := {
		"k": killer_peer_id, "v": victim_peer_id, "kn": killer_name, "vn": victim_name,
		"kt": team_id, "vt": victim_team, "w": String(weapon_id), "hs": headshot, "tags": tag,
	}
	if not tricks.is_empty():
		_award_style(kill_info, tricks)
	if _round_active:
		final_kill = kill_info
	if is_ffa():
		_check_win_player(killer_peer_id)
	else:
		_check_win_team(team_id)
	_bump_streak(killer_peer_id, victim_peer_id)


## Own grenade or own RC: kill feed shows it, this life's kill count resets, banked streaks stay.
func _register_suicide(peer_id: int, weapon_id: StringName) -> void:
	_hs_streak.erase(peer_id)
	var n := _display_name_for(peer_id)
	if scores.has(peer_id):
		n = str(scores[peer_id].name)
	var team := 0
	var p := player_for_peer(peer_id)
	if p:
		team = p.team_id
	elif scores.has(peer_id):
		team = int(scores[peer_id].get("team", 0))
	_emit_kill_feed(n, n, weapon_id, team, team, "")
	if is_networked():
		sync_kill_feed.rpc(n, n, String(weapon_id), team, team, "")
	_bump_streak(0, peer_id)


func _add_team_kill(team_id: int) -> void:
	var t := clampi(team_id, TEAM_A, TEAM_B)
	team_kills[t] = int(team_kills[t]) + 1
	if is_networked() and multiplayer.is_server():
		sync_team_kills.rpc(int(team_kills[0]), int(team_kills[1]))


@rpc("authority", "reliable")
func sync_team_kills(blue: int, orange: int) -> void:
	team_kills = [blue, orange]


const STREAK_AT := 3 # radar
const RCXD_AT := 5
const RADAR_TIME := 4.0
const CHARGE_RADAR := 1
const CHARGE_RCXD := 2

var streak_progress: Dictionary = {} # peer -> kills this life (death clears this)
var streak_charges: Dictionary = {} # peer -> bitmask of streaks earned and not yet used
var streak_earned: Dictionary = {} # peer -> bitmask already passed this life (stops a second copy)


## Humans only. Death clears this life's count, not a streak already earned.
## 3 banks the radar, 5 banks the RC-XD. Each stays until Enter uses it,
## or until start_round clears every charge for the next round.
func _bump_streak(killer_peer_id: int, victim_peer_id: int) -> void:
	if victim_peer_id > 0:
		streak_progress[victim_peer_id] = 0
		streak_earned[victim_peer_id] = 0
		_push_streak(victim_peer_id)
	if killer_peer_id <= 0:
		return
	var n := int(streak_progress.get(killer_peer_id, 0))
	if n < RCXD_AT:
		n += 1
	streak_progress[killer_peer_id] = n
	var charges := int(streak_charges.get(killer_peer_id, 0))
	var earned := int(streak_earned.get(killer_peer_id, 0))
	if n >= STREAK_AT and (earned & CHARGE_RADAR) == 0:
		earned |= CHARGE_RADAR
		charges |= CHARGE_RADAR
	if n >= RCXD_AT and (earned & CHARGE_RCXD) == 0:
		earned |= CHARGE_RCXD
		charges |= CHARGE_RCXD
	streak_earned[killer_peer_id] = earned
	streak_charges[killer_peer_id] = charges
	_push_streak(killer_peer_id)


func _push_streak(peer_id: int) -> void:
	var n := int(streak_progress.get(peer_id, 0))
	var charges := int(streak_charges.get(peer_id, 0))
	var earned := int(streak_earned.get(peer_id, 0))
	if not is_networked() or peer_id == multiplayer.get_unique_id():
		_apply_streak_local(n, charges, earned)
		return
	sync_streak.rpc_id(peer_id, n, charges, earned)


@rpc("authority", "reliable")
func sync_streak(n: int, charges: int, earned: int) -> void:
	_apply_streak_local(n, charges, earned)


func _apply_streak_local(n: int, charges: int, earned: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_streak(n, charges, earned)


## Slot 0 is the radar (3), slot 1 is the RC-XD (5). Using one spends only that charge.
## Radar still spends if one is already running (time is not stacked).
## Freeze, killcam, death, or a car already out: the charge is kept.
func try_activate_streak(peer_id: int, slot: int) -> void:
	if not _is_match_authority():
		return
	if play_locked() or peer_id <= 0:
		return
	var p := player_for_peer(peer_id)
	if p == null or p.is_dead or p.is_bot:
		return
	if RcXd.for_owner(peer_id) != null:
		return
	var bit := 0
	if slot == 0:
		bit = CHARGE_RADAR
	elif slot == 1:
		bit = CHARGE_RCXD
	else:
		return
	var charges := int(streak_charges.get(peer_id, 0))
	if (charges & bit) == 0:
		return
	if bit == CHARGE_RCXD and not RcXd.launch(p):
		return
	charges &= ~bit
	streak_charges[peer_id] = charges
	_push_streak(peer_id)
	if bit == CHARGE_RADAR:
		_grant_radar(peer_id)


## HUD calls this. Clients cannot grant their own radar.
func request_use_streak(slot: int) -> void:
	if is_networked() and not multiplayer.is_server():
		request_streak.rpc_id(1, slot)
	else:
		var id := multiplayer.get_unique_id() if is_networked() else 1
		try_activate_streak(id, slot)


@rpc("any_peer", "reliable")
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


## Driver's yaw and throttle. The server car is the one that explodes.
@rpc("any_peer", "unreliable")
func rc_drive(net_id: int, yaw_in: float, throttle_in: float) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var car := RcXd.authority_by_id(net_id)
	if car == null or car.owner_peer != peer:
		return
	car.apply_remote_input(yaw_in, throttle_in)


@rpc("any_peer", "reliable")
func rc_detonate(net_id: int) -> void:
	if not multiplayer.is_server() or play_locked():
		return
	var peer := multiplayer.get_remote_sender_id()
	var car := RcXd.authority_by_id(net_id)
	if car == null or car.owner_peer != peer:
		return
	car.shutdown(true)


## Visual copy on clients. The driver's copy simulates; the rest follow poses.
@rpc("authority", "reliable")
func sync_rc_spawn(net_id: int, peer: int, team: int, pos: Vector3, yaw_in: float) -> void:
	if multiplayer.is_server() or _rc_done.has(net_id):
		return
	RcXd.spawn_visual(net_id, peer, team, pos, yaw_in)


@rpc("authority", "unreliable")
func sync_rc_pose(net_id: int, pos: Vector3, yaw_in: float, life_in: float) -> void:
	if multiplayer.is_server() or _rc_done.has(net_id):
		return
	var car := RcXd.by_id(net_id)
	if car:
		car.apply_net_pose(pos, yaw_in, life_in)


@rpc("authority", "reliable")
func sync_rc_end(net_id: int, pos: Vector3, exploded: bool) -> void:
	if multiplayer.is_server():
		return
	_rc_done[net_id] = true
	var car := RcXd.by_id(net_id)
	if car:
		car.client_end(exploded, pos)
	elif exploded and not is_dedicated:
		Grenade.play_boom(pos)


@rpc("authority", "reliable")
func sync_rc_hp(net_id: int, value: float) -> void:
	if multiplayer.is_server():
		return
	var car := RcXd.by_id(net_id)
	if car:
		car.apply_hp(value)


## Same popup split as the radar: your team sees RC-XD, the other team sees ENEMY RC-XD.
func announce_rc(peer_id: int, team: int) -> void:
	var by := _display_name_for(peer_id)
	if scores.has(peer_id):
		by = str(scores[peer_id].name)
	if is_networked():
		sync_rc_announce.rpc(team, by, peer_id)
	_apply_rc_announce(team, by, peer_id)


@rpc("authority", "reliable")
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


## Team radar (UAV): every machine hears about it; the activator's team gets the markers,
## the other team only the "enemy radar" cue. Markers follow the pawns (Player._process), so
## enemies that respawn during the radar show up too. FFA: only the activator gets markers
## (of everyone else); all others get the "enemy radar" cue.
func _grant_radar(peer_id: int) -> void:
	var team := 0
	var p := player_for_peer(peer_id)
	if p:
		team = p.team_id
	elif scores.has(peer_id):
		team = int(scores[peer_id].get("team", 0))
	var by := _display_name_for(peer_id)
	if scores.has(peer_id):
		by = str(scores[peer_id].name)
	if is_networked():
		sync_radar.rpc(team, by, RADAR_TIME, peer_id)
	_apply_radar(team, by, RADAR_TIME, peer_id)


@rpc("authority", "reliable")
func sync_radar(team: int, by_name: String, seconds: float, by_peer: int) -> void:
	if multiplayer.is_server():
		return
	_apply_radar(team, by_name, clampf(seconds, 0.0, RADAR_TIME), by_peer)


func _apply_radar(team: int, by_name: String, seconds: float, by_peer: int) -> void:
	var mine := local_team()
	if mine < 0:
		return
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	var friendly := team == mine
	if is_ffa():
		friendly = by_peer == multiplayer.get_unique_id()
	if friendly:
		radar_team = team
		radar_peer = by_peer
		radar_left = maxf(radar_left, seconds)
	if hud:
		hud.show_radar_event(by_name, team, friendly)


## Round end, round start, killcam, and leaving: no markers carry over, and no RC stays out.
func clear_radar() -> void:
	radar_left = 0.0
	radar_team = -1
	radar_peer = 0
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.clear_radar()
	RcXd.abort_all()


func _emit_kill_feed(
	killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int, tricks: String
) -> void:
	kill_feed.emit(killer_name, victim_name, weapon_id, killer_team, victim_team, tricks)


@rpc("authority", "reliable")
func sync_kill_feed(
	killer_name: String, victim_name: String, weapon_id: String, killer_team: int, victim_team: int, tricks: String = ""
) -> void:
	if multiplayer.is_server():
		return
	kill_feed.emit(killer_name, victim_name, StringName(weapon_id), killer_team, victim_team, tricks.left(80))


# --- Trickshots / style (see Style). Match authority decides, everyone shows it. ---

## The shot (or melee swing) resolving right now (Game._shot_ctx) made this kill: what tricks was it?
## Grenades and anything outside a shot or swing have no context and no tricks.
func _detect_tricks(
	killer_peer_id: int, victim_peer_id: int, weapon_id: StringName, headshot: bool = false
) -> Array[StringName]:
	var none: Array[StringName] = []
	if _shot_ctx.is_empty():
		return none
	var shooter := _shot_ctx.get("shooter") as Player
	if shooter == null or not is_instance_valid(shooter):
		return none
	if shooter.peer_id != killer_peer_id and shooter._owner_peer() != killer_peer_id:
		return none
	var victim := player_for_peer(victim_peer_id)
	var origin: Vector3 = _shot_ctx.get("origin", shooter.global_position)
	var dist := origin.distance_to(victim.aim_point()) if victim else 0.0
	var window := Style.SPIN_WINDOW
	if is_networked() and not shooter.is_bot and not shooter.is_local():
		window += Style.SPIN_NET_SLACK
	var now := Time.get_ticks_msec() / 1000.0
	var burst: Dictionary = _shot_ctx.get("burst", {})
	var others := 0
	for v in burst.get("victims", []):
		if int(v) != victim_peer_id:
			others += 1
	var streak := int(_hs_streak.get(killer_peer_id, 0))
	if weapon_id == &"rifle" and headshot:
		streak += 1
	var mag: Dictionary = _shot_ctx.get("mag", {})
	var mag_kills := int(mag.get("kills", 0)) + 1 if StringName(mag.get("weapon", &"")) == weapon_id else 0
	var since_draw := INF
	if shooter.weapon and shooter.weapon.def and shooter.weapon.def.id == weapon_id:
		since_draw = shooter.weapon.since_draw()
	var remote := is_networked() and not shooter.is_bot and not shooter.is_local()
	return Style.detect({
		"weapon": weapon_id,
		"scoped": bool(_shot_ctx.get("scoped", false)),
		"bot": shooter.is_bot,
		"headshot": headshot,
		"spin": shooter.spin_degrees(window),
		"shooter_air": shooter.air_time,
		"victim_air": victim.air_time if victim else 0.0,
		"dist": dist,
		"speed": shooter._obs_speed,
		"surf": shooter.style_surfing(),
		"drop": shooter.style_drop(),
		"burst_victims": others,
		"double": weapon_id == &"shotgun" and now - float(_shotgun_kill_t.get(killer_peer_id, -100.0)) <= Style.DOUBLE_WINDOW,
		"hs_streak": streak,
		"run_t": shooter.run_time(),
		"mag_kills": mag_kills,
		"since_draw": since_draw,
		"quickdraw_slack": Style.QUICKDRAW_NET_SLACK if remote else 0.0,
		"knife_air": bool(_shot_ctx.get("knife_air", false)),
	})


## Per-killer history behind DOUBLE, SPRAY TRANSFER and HEADSHOT STREAK (after _detect_tricks).
func _note_trick_history(killer_peer_id: int, victim_peer_id: int, weapon_id: StringName, headshot: bool) -> void:
	_hs_streak.erase(victim_peer_id) # dying ends your streak
	if weapon_id == &"rifle" and headshot:
		_hs_streak[killer_peer_id] = int(_hs_streak.get(killer_peer_id, 0)) + 1
	else:
		_hs_streak.erase(killer_peer_id) # any other kill breaks the run
	if weapon_id == &"shotgun":
		_shotgun_kill_t[killer_peer_id] = Time.get_ticks_msec() / 1000.0
	if not _shot_ctx.is_empty():
		var burst: Dictionary = _shot_ctx.get("burst", {})
		if not burst.is_empty():
			(burst.victims as Array).append(victim_peer_id)
		var mag: Dictionary = _shot_ctx.get("mag", {})
		if not mag.is_empty() and StringName(mag.get("weapon", &"")) == weapon_id:
			mag.kills = int(mag.kills) + 1


## Points (with the chain multiplier) onto the killer's style; tell everyone; remember the round's best
## trick for the final killcam.
func _award_style(kill_info: Dictionary, tricks: Array[StringName]) -> void:
	var k := int(kill_info.k)
	var now := Time.get_ticks_msec() / 1000.0
	var prev: Array = _style_chain.get(k, [0, -1000.0])
	var chain := int(prev[0]) + 1 if now - float(prev[1]) <= Style.CHAIN_WINDOW else 1
	_style_chain[k] = [chain, now]
	var pts := Style.award(tricks, chain)
	var mult := Style.chain_multiplier(chain)
	var total := pts + (int(scores[k].get("style", 0)) if scores.has(k) else 0)
	_trick_seq += 1
	var is_best := _round_active and pts > int(best_trick.get("pts", 0))
	if is_best:
		best_trick = kill_info.duplicate()
		best_trick["pts"] = pts
		best_trick["trick_id"] = _trick_seq
	var packed := Style.pack(tricks)
	_apply_trick(k, int(kill_info.v), packed, pts, mult, total, _trick_seq, is_best)
	if is_networked():
		sync_trick.rpc(k, int(kill_info.v), packed, pts, mult, total, _trick_seq, is_best)


@rpc("authority", "reliable")
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


## Most style this round (> 0). Ties: the name that sorts first. {} if nobody has style.
func style_king() -> Dictionary:
	var best := {}
	for id in scores:
		var st := int(scores[id].get("style", 0))
		if st <= 0:
			continue
		var n := str(scores[id].name)
		if best.is_empty() or st > int(best.style) or (st == int(best.style) and n < str(best.name)):
			best = {"peer_id": int(id), "name": n, "style": st, "team": int(scores[id].get("team", 0))}
	return best


## `style` -1 keeps the row's style (only the round reset sends 0).
@rpc("authority", "reliable")
func sync_score(peer_id: int, score: int, n: String, team: int = 0, style: int = -1) -> void:
	_apply_score(peer_id, score, n, team)
	if style >= 0 and scores.has(peer_id):
		scores[peer_id].style = style


@rpc("authority", "reliable")
func sync_round_end(winner_peer_id: int, winner_name: String, round_scores: Dictionary) -> void:
	_round_active = false # hides the HUD clock on clients too
	clear_radar()
	round_ended.emit(winner_peer_id, winner_name, round_scores)


@rpc("authority", "reliable")
func sync_round_time(time_left: float) -> void:
	_round_timer = round_time - time_left
	_round_active = time_left > 0.0


@rpc("authority", "reliable")
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


func _check_win_team(team_id: int) -> void:
	if not _round_active:
		return
	if get_team_kills(team_id) >= win_kills():
		_end_round_team(team_id)


## FFA: first player to kill_limit wins the round.
func _check_win_player(peer_id: int) -> void:
	if not _round_active or not scores.has(peer_id):
		return
	if int(scores[peer_id].kills) >= win_kills():
		_end_round_player(peer_id)


## FFA round end: `winner_name` is the player. round_ended carries the peer id (TDM: the team id).
func _end_round_player(peer_id: int) -> void:
	_round_active = false
	clear_radar()
	var winner_name := _display_name_for(peer_id)
	if scores.has(peer_id):
		winner_name = str(scores[peer_id].name)
	if peer_id == 0:
		winner_name = "Nobody"
	round_ended.emit(peer_id, winner_name, scores.duplicate())
	if is_networked():
		sync_round_end.rpc(peer_id, winner_name, scores.duplicate())


func _end_round(winner_peer_id: int) -> void:
	if is_ffa():
		_end_round_player(winner_peer_id)
		return
	var team := 0
	if scores.has(winner_peer_id):
		team = int(scores[winner_peer_id].get("team", 0))
	_end_round_team(team)


func _end_round_team(team_id: int) -> void:
	_round_active = false
	clear_radar()
	var winner_name: String = TEAM_NAMES[clampi(team_id, 0, TEAM_NAMES.size() - 1)]
	round_ended.emit(team_id, winner_name, scores.duplicate())
	if is_networked():
		sync_round_end.rpc(team_id, winner_name, scores.duplicate())


func notify_intermission() -> void:
	intermission_started.emit()
	if is_networked() and multiplayer.is_server():
		sync_intermission.rpc()


@rpc("authority", "reliable")
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
	else:
		stop_round_sting()
	if is_networked() and multiplayer.is_server():
		sync_round_frozen.rpc(on)


@rpc("authority", "reliable")
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
	else:
		stop_round_sting()


func play_round_sting() -> void:
	if _round_music and _round_music.stream:
		_round_music.play()


func stop_round_sting() -> void:
	if _round_music and _round_music.playing:
		_round_music.stop()


func start_round() -> void:
	_round_timer = 0.0
	_round_active = false # timer starts after freeze
	final_kill.clear()
	best_trick.clear()
	_style_chain.clear()
	_line_cd.clear()
	_line_chain.clear()
	_line_pos.clear()
	_bursts.clear()
	_shotgun_kill_t.clear()
	_hs_streak.clear()
	_mags.clear()
	team_kills = [0, 0]
	if is_networked() and multiplayer.is_server():
		sync_team_kills.rpc(0, 0)
	for id in scores:
		scores[id].style = 0
		_apply_score(id, 0, str(scores[id].name), int(scores[id].get("team", 0)))
		if is_networked() and multiplayer.is_server():
			sync_score.rpc(id, 0, str(scores[id].name), int(scores[id].team), 0)
	_clear_round_streaks()


## New round drops this life's kill count and any charge still held.
## Leave-to-menu clears the same dictionaries in reset_session. Without this, a radar
## banked last round is still usable after intermission. Clients hear it via sync_streak.
func _clear_round_streaks() -> void:
	var humans := {}
	for src in [streak_progress, streak_charges, streak_earned]:
		for id in src:
			if int(id) > 0:
				humans[int(id)] = true
	streak_progress.clear()
	streak_charges.clear()
	streak_earned.clear()
	var me := multiplayer.get_unique_id() if is_networked() else 1
	if me > 0:
		humans[me] = true
	for id in humans:
		_push_streak(int(id))


func end_freeze() -> void:
	_round_active = true
	_round_timer = 0.0
	set_round_frozen(false)
	if is_networked() and multiplayer.is_server():
		sync_round_time.rpc(round_time)


## Late joiner: scores, team totals, freeze, and clock, so the HUD is right from the first frame.
func send_match_state(peer_id: int) -> void:
	if not is_networked() or not multiplayer.is_server():
		return
	sync_match_config.rpc_id(peer_id, String(map_id), mode, kill_limit, round_time)
	var scores_arr := get_scores()
	if scores_arr.size() > 0:
		sync_all_scores.rpc_id(peer_id, scores_arr)
	sync_team_kills.rpc_id(peer_id, int(team_kills[0]), int(team_kills[1]))
	if round_frozen:
		sync_round_frozen.rpc_id(peer_id, true)
	if killcam_active:
		killcam.send_lock_to(peer_id)
	if _round_active:
		sync_round_time.rpc_id(peer_id, get_round_time_left())


## Leave to menu: nothing from the old session may leak into the next one.
func reset_session() -> void:
	scores.clear()
	pings.clear()
	net_hp.clear()
	_regen_dirty.clear()
	lobby.clear()
	streak_progress.clear()
	streak_charges.clear()
	streak_earned.clear()
	rc_view = false
	_rc_done.clear()
	pending_names.clear()
	pending_teams.clear()
	_fire_credit.clear()
	team_kills = [0, 0]
	in_lobby = false
	round_frozen = false
	killcam_active = false
	final_kill.clear()
	best_trick.clear()
	_style_chain.clear()
	_line_cd.clear()
	_line_chain.clear()
	_line_pos.clear()
	_bursts.clear()
	_shotgun_kill_t.clear()
	_hs_streak.clear()
	_mags.clear()
	_shot_ctx = {}
	if killcam:
		killcam.reset()
	if melee:
		melee.reset()
	if impacts:
		impacts.clear()
	if loadouts:
		loadouts.reset()
	clear_radar()
	_round_active = false
	_round_timer = 0.0
	stop_round_sting()
	Engine.time_scale = 1.0
	for id in _grenade_visuals:
		var vis: Node = _grenade_visuals[id]
		if is_instance_valid(vis):
			vis.queue_free()
	_grenade_visuals.clear()
	_grenade_done.clear()
	for g in get_tree().get_nodes_in_group("grenade"):
		g.queue_free()
	_knife_visuals.clear()
	for k in get_tree().get_nodes_in_group("knife"):
		k.queue_free()


func update_round_timer(delta: float) -> bool:
	if not _round_active:
		return false
	_round_timer += delta
	if _round_timer >= round_time:
		if is_ffa():
			_end_round_player(top_player())
		else:
			_end_round_team(_get_leader())
		return true
	return false


func _get_leader() -> int:
	if get_team_kills(TEAM_A) >= get_team_kills(TEAM_B):
		return TEAM_A
	return TEAM_B


## FFA leader: most kills; a tie goes to the name that sorts first (same order as the board).
func top_player() -> int:
	var board := get_scores()
	if board.is_empty() or int(board[0].kills) <= 0:
		return 0
	return int(board[0].peer_id)


func get_team_kills(team_id: int) -> int:
	return int(team_kills[clampi(team_id, TEAM_A, TEAM_B)])


func get_scores() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in scores:
		out.append({
			"peer_id": id,
			"name": scores[id].name,
			"kills": scores[id].kills,
			"team": int(scores[id].get("team", 0)),
			"style": int(scores[id].get("style", 0)),
			"ping": int(pings.get(id, -1)),
		})
	out.sort_custom(_sort_scores)
	return out


func _sort_scores(a: Dictionary, b: Dictionary) -> bool:
	if not is_ffa() and int(a.get("team", 0)) != int(b.get("team", 0)):
		return int(a.team) < int(b.team)
	if a.kills == b.kills:
		return str(a.name) < str(b.name)
	return a.kills > b.kills


func get_round_time_left() -> float:
	return maxf(round_time - _round_timer, 0.0)


## Host already played local FX. Remote humans need a tracer/sfx on the listen-server too.
func broadcast_shot_fx(from: Vector3, to: Vector3, shooter_peer_id: int) -> void:
	if not is_networked() or not multiplayer.is_server():
		return
	if shooter_peer_id > 0 and shooter_peer_id != multiplayer.get_unique_id():
		_spawn_net_tracer(from, to)
		var remote_shooter := player_for_peer(shooter_peer_id)
		if remote_shooter and remote_shooter.weapon:
			remote_shooter.weapon.play_fire_sfx()
		_note_net_shot(from, to, remote_shooter)
	sync_shot_fx.rpc(from, to, shooter_peer_id)


## Skip the shooter: they already spawned tracers locally in Weapon._fire.
@rpc("authority", "unreliable")
func sync_shot_fx(from: Vector3, to: Vector3, shooter_peer_id: int = 0) -> void:
	if shooter_peer_id != 0 and shooter_peer_id == multiplayer.get_unique_id():
		return
	_spawn_net_tracer(from, to)
	var shooter := player_for_peer(shooter_peer_id)
	if shooter and shooter.weapon:
		shooter.weapon.play_fire_sfx()
	_note_net_shot(from, to, shooter)


## Someone else's shot as this machine saw it, for the killcam buffer. Own shots are noted in Weapon._fire.
func _note_net_shot(from: Vector3, to: Vector3, shooter: Player) -> void:
	if shooter == null or shooter.weapon == null or shooter.weapon.def == null:
		return
	killcam.note_fire(shooter.peer_id, shooter.weapon.def.id)
	killcam.note_tracer(shooter.peer_id, from, to, shooter.weapon.def.id)


func _spawn_net_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	impacts.add_from_tracer(from, to)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_energy_multiplier = 3.0
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(mesh_inst)
	mesh_inst.global_position = (from + to) * 0.5
	if from.distance_squared_to(to) > 0.0001:
		mesh_inst.look_at(to, Vector3.UP)
	get_tree().create_timer(0.055).timeout.connect(mesh_inst.queue_free)


## Host is 0 ms. Bots are -1 (shown as —). Clients get ENet RTT from the server.
func _sample_pings() -> void:
	if not is_networked() or not multiplayer.is_server():
		return
	pings[multiplayer.get_unique_id()] = 0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		for id in multiplayer.get_peers():
			var ep := enet.get_peer(int(id))
			if ep == null or not ep.is_active():
				continue
			pings[int(id)] = int(ep.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	for id in scores:
		if int(id) < 0:
			pings[id] = -1
	if not multiplayer.get_peers().is_empty():
		sync_pings.rpc(pings)


@rpc("authority", "unreliable")
func sync_pings(data: Dictionary) -> void:
	if multiplayer.is_server():
		return
	pings = data


## Match authority. A human pawn crossing a speed strip fast enough banks LINE (or LINE ×2).
## The segment test catches a snapshot that steps through the box. Bots never surf, so they skip it.
## is_best stays false: a strip is not a kill, and it must not replace the round's killcam.
func _tick_lines(delta: float) -> void:
	if not _is_match_authority():
		return
	_decay_line_clocks(delta)
	var strips := get_tree().get_nodes_in_group("speed_strip")
	if strips.is_empty():
		return
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_bot or p.is_dead:
			continue
		var prev: Vector3 = _line_pos.get(p.peer_id, p.global_position)
		var step := p.global_position - prev
		_line_pos[p.peer_id] = p.global_position
		if step.length() > Player.STRIP_TELEPORT_M:
			continue
		var spd := Vector2(step.x, step.z).length() / maxf(delta, 0.0001)
		if spd < Player.STRIP_SPEED:
			continue
		for s in strips:
			var strip := s as Node3D
			if strip == null or not Player.segment_hits_strip(strip, prev, p.global_position):
				continue
			_award_line(p.peer_id, str(strip.name))
			break


func _decay_line_clocks(delta: float) -> void:
	var gone: Array[int] = []
	for id in _line_cd:
		var left: Dictionary = _line_cd[id]
		var names: Array = left.keys()
		for sname in names:
			left[sname] = float(left[sname]) - delta
			if float(left[sname]) <= 0.0:
				left.erase(sname)
		if left.is_empty():
			gone.append(int(id))
	for id in gone:
		_line_cd.erase(id)
	gone.clear()
	for id in _line_chain:
		var row: Array = _line_chain[id]
		row[1] = float(row[1]) - delta
		if float(row[1]) <= 0.0:
			gone.append(int(id))
	for id in gone:
		_line_chain.erase(id)


## Same wire as a trickshot, without the kill chain and without touching best_trick.
func _award_line(peer_id: int, strip_name: String) -> void:
	if not scores.has(peer_id):
		return
	var cd: Dictionary = _line_cd.get(peer_id, {})
	if float(cd.get(strip_name, 0.0)) > 0.0:
		return
	cd[strip_name] = Player.STRIP_COOLDOWN
	_line_cd[peer_id] = cd
	var trick := Style.LINE
	var prev: Array = _line_chain.get(peer_id, ["", 0.0])
	if str(prev[0]) != "" and str(prev[0]) != strip_name and float(prev[1]) > 0.0:
		trick = Style.LINE_X2
	_line_chain[peer_id] = [strip_name, Player.CARRY_TIME]
	var pts := int(Style.POINTS[trick])
	var total := pts + int(scores[peer_id].get("style", 0))
	_trick_seq += 1
	var packed := Style.pack([trick])
	_apply_trick(peer_id, 0, packed, pts, 1.0, total, _trick_seq, false)
	if is_networked() and multiplayer.is_server():
		sync_trick.rpc(peer_id, 0, packed, pts, 1.0, total, _trick_seq, false)


## Listen-server: bots have MultiplayerSynchronizer off, so we push poses ourselves.
func _physics_process(delta: float) -> void:
	_tick_regen(delta)
	_tick_lines(delta)
	if radar_left > 0.0:
		radar_left = maxf(radar_left - delta, 0.0)
	if not is_networked() or not multiplayer.is_server():
		return
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
		poses.append([p.peer_id, p.global_position, p.rotation.y, p.head.rotation.x])
	if poses.is_empty():
		return
	sync_bot_poses.rpc(poses)


## Health regen on the match authority: REGEN_DELAY s after the last hit, REGEN_RATE HP/s (bots too).
## Clients get the values in batches every REGEN_SYNC s; the last step to full HP is sent at once.
func _tick_regen(delta: float) -> void:
	if not _is_match_authority():
		return
	var to_send := false
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead or p.is_queued_for_deletion():
			continue
		p.since_hurt += delta
		var cur := hp_of(p)
		if cur >= Player.MAX_HP or p.since_hurt < Player.REGEN_DELAY:
			continue
		var new_hp := minf(cur + Player.REGEN_RATE * delta, Player.MAX_HP)
		set_hp(p, new_hp)
		p.apply_regen_hp(new_hp)
		_regen_dirty[p.peer_id] = new_hp
		if new_hp >= Player.MAX_HP:
			to_send = true
	if not is_networked():
		_regen_dirty.clear()
		return
	_regen_sync_t -= delta
	if _regen_dirty.is_empty() or (_regen_sync_t > 0.0 and not to_send):
		return
	_regen_sync_t = REGEN_SYNC
	var batch: Array = []
	for id in _regen_dirty:
		batch.append([id, float(_regen_dirty[id])])
	_regen_dirty.clear()
	if not multiplayer.get_peers().is_empty():
		sync_regen.rpc(batch)


@rpc("authority", "reliable")
func sync_regen(batch: Array) -> void:
	if multiplayer.is_server():
		return
	for entry in batch:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 2:
			continue
		var p := player_for_peer(int(entry[0]))
		if p:
			p.apply_regen_hp(clampf(float(entry[1]), 0.0, Player.MAX_HP))


@rpc("authority", "unreliable")
func sync_bot_poses(poses: Array) -> void:
	if multiplayer.is_server():
		return
	for entry in poses:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 4:
			continue
		var p := player_for_peer(int(entry[0]))
		if p and p.is_bot:
			p.apply_network_pose(entry[1], float(entry[2]), float(entry[3]))


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
@rpc("any_peer", "reliable")
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


@rpc("authority", "reliable")
func sync_weapon(peer_id: int, weapon_id: String) -> void:
	if multiplayer.is_server():
		return
	var p := player_for_peer(peer_id)
	if p == null or p.is_local() or p.weapon == null:
		return
	p.weapon.equip_remote(StringName(weapon_id))


func live_peer_ids() -> Array:
	var ids: Array = []
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and not p.is_queued_for_deletion():
			ids.append(p.peer_id)
	return ids


func broadcast_roster() -> void:
	if not is_networked() or not multiplayer.is_server():
		return
	sync_roster.rpc(live_peer_ids())


## Client deletes pawns the server no longer has (ghost bots after join-replace).
@rpc("authority", "reliable")
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
	_ensure_sfx_bus()
	load_settings()
	_bind_inputs()
	_round_music = AudioStreamPlayer.new()
	_round_music.bus = "Master"
	_round_music.stream = load("res://assets/sounds/round_start.wav")
	add_child(_round_music)


func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index("SFX") != -1:
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


## Reads user://settings.cfg. Missing keys keep the defaults, so an older file (audio + mouse
## only) still loads. Applies audio and, unless this process is headless, the video settings.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		master_vol = clampf(float(cfg.get_value("audio", "master", 1.0)), 0.0, 1.0)
		sfx_vol = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
		mouse_sens = clampf(float(cfg.get_value("input", "mouse_sens", 1.0)), MOUSE_SENS_MIN, MOUSE_SENS_MAX)
		ads_sens = clampf(float(cfg.get_value("input", "ads_sens", 0.45)), ADS_SENS_MIN, ADS_SENS_MAX)
		invert_y = bool(cfg.get_value("input", "invert_y", false))
		var m := StringName(str(cfg.get_value("match", "map", String(Maps.DEFAULT))))
		last_map = m if Maps.has(m) else Maps.DEFAULT
		last_mode = clampi(int(cfg.get_value("match", "mode", MODE_TDM)), MODE_TDM, MODE_FFA)
		last_kills = clampi(int(cfg.get_value("match", "kills", default_kills_for(last_mode))), KILLS_MIN, KILLS_MAX)
		last_time_min = clampi(int(cfg.get_value("match", "time_min", 10)), TIME_MIN_MINUTES, TIME_MAX_MINUTES)
		last_bots = clampi(int(cfg.get_value("match", "bots", BOT_COUNT_DEFAULT)), 0, BOT_COUNT_MAX)
		kill_limit = last_kills
		round_time = float(last_time_min * 60)
		bot_count = last_bots
		profile_name = clean_name(str(cfg.get_value("profile", "name", profile_name)))
		player_name = profile_name
		window_mode = clampi(int(cfg.get_value("video", "window_mode", WINDOW_WINDOWED)), WINDOW_WINDOWED, WINDOW_FULLSCREEN)
		var w := int(cfg.get_value("video", "width", window_size.x))
		var h := int(cfg.get_value("video", "height", window_size.y))
		if w < 640 or h < 480:
			w = 1600
			h = 900
		window_size = Vector2i(w, h)
		vsync = bool(cfg.get_value("video", "vsync", true))
		max_fps = _snap_fps(int(cfg.get_value("video", "max_fps", 0)))
		fov = clampf(roundf(float(cfg.get_value("video", "fov", 90.0))), FOV_MIN, FOV_MAX)
		render_scale = _snap_scale(float(cfg.get_value("video", "render_scale", 1.0)))
		msaa = clampi(int(cfg.get_value("video", "msaa", 2)), 0, 3)
		show_fps = bool(cfg.get_value("hud", "show_fps", true))
	apply_audio()
	var size_before := window_size
	apply_display()
	# A size that does not fit this monitor is replaced; remember the one we actually used.
	if window_size != size_before:
		save_settings()


## Rewrites the whole file from memory. Every key load_settings reads has to be written here.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_vol)
	cfg.set_value("audio", "sfx", sfx_vol)
	cfg.set_value("input", "mouse_sens", mouse_sens)
	cfg.set_value("input", "ads_sens", ads_sens)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("match", "map", String(last_map))
	cfg.set_value("match", "mode", last_mode)
	cfg.set_value("match", "kills", last_kills)
	cfg.set_value("match", "time_min", last_time_min)
	cfg.set_value("match", "bots", last_bots)
	cfg.set_value("profile", "name", profile_name)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "width", window_size.x)
	cfg.set_value("video", "height", window_size.y)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "msaa", msaa)
	cfg.set_value("hud", "show_fps", show_fps)
	cfg.save("user://settings.cfg")


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
	if in_lobby:
		pending_names[peer] = player_name
		var team := preferred_team
		if lobby.has(peer):
			team = int(lobby[peer].get("team", team))
		set_lobby_member(peer, player_name, team)
		_retitle()
		return
	if player_for_peer(peer) != null or scores.has(peer):
		if is_networked():
			apply_display_name.rpc(peer, player_name)
		else:
			apply_display_name(peer, player_name)
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
func remember_match_choice(m: StringName, md: int, kills: int = -1, time_min: int = -1, bots: int = -1) -> void:
	last_map = m
	last_mode = md
	if kills >= 0:
		last_kills = clampi(kills, KILLS_MIN, KILLS_MAX)
	if time_min >= 0:
		last_time_min = clampi(time_min, TIME_MIN_MINUTES, TIME_MAX_MINUTES)
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


func set_show_fps(on: bool) -> void:
	show_fps = on
	save_settings()
	if not is_inside_tree():
		return
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


func set_msaa(v: int) -> void:
	msaa = clampi(v, 0, 3)
	apply_render()
	save_settings()


## True for `./run.sh --headless` and the dedicated server. Video settings must not touch the window.
func display_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Presets that fit the current monitor, plus that monitor's own size when it is not already listed.
func resolution_choices() -> Array:
	var screen := Vector2i(1920, 1080)
	if not display_headless():
		screen = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return _resolutions_fitting(screen)


func _resolutions_fitting(screen: Vector2i) -> Array:
	var out: Array[Vector2i] = []
	for r in RESOLUTIONS:
		var size := r as Vector2i
		if size.x <= screen.x and size.y <= screen.y:
			out.append(size)
	var listed := false
	for size in out:
		if size == screen:
			listed = true
			break
	if not listed and screen.x >= 640 and screen.y >= 480:
		out.append(screen)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	if out.is_empty():
		out.append(Vector2i(mini(maxi(screen.x, 640), 1280), mini(maxi(screen.y, 480), 720)))
	return out


## Window, VSync, the FPS cap, 3D scale and MSAA. Headless returns immediately; main.gd then
## pins a dedicated server to 60 fps. A saved size bigger than this monitor is replaced with
## the largest preset that fits, and load_settings writes that back.
func apply_display() -> void:
	if display_headless():
		return
	_apply_vsync_and_fps()
	_apply_window()
	apply_render()


func _apply_vsync_and_fps() -> void:
	if display_headless():
		return
	var want_vsync := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != want_vsync:
		DisplayServer.window_set_vsync_mode(want_vsync)
	if Engine.max_fps != max_fps:
		Engine.max_fps = max_fps


func _apply_window() -> void:
	var screen_id := DisplayServer.window_get_current_screen()
	var screen := DisplayServer.screen_get_size(screen_id)
	var fit := _clamp_window_size(window_size, screen)
	if fit != window_size:
		window_size = fit
	var mode_now := DisplayServer.window_get_mode()
	if window_mode == WINDOW_BORDERLESS:
		# Borderless follows the monitor. The stored size is for windowed / exclusive only.
		if mode_now != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if window_mode == WINDOW_FULLSCREEN:
		if mode_now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN and DisplayServer.window_get_size() == window_size:
			return
		# Leave exclusive before changing size, or the mode switch keeps the old resolution.
		if mode_now != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		return
	var size_now := DisplayServer.window_get_size()
	if mode_now != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	if size_now != window_size:
		DisplayServer.window_set_size(window_size)
		var origin := DisplayServer.screen_get_position(screen_id)
		DisplayServer.window_set_position(origin + (screen - window_size) / 2)


func _clamp_window_size(size: Vector2i, screen: Vector2i) -> Vector2i:
	if size.x >= 640 and size.y >= 480 and size.x <= screen.x and size.y <= screen.y:
		return size
	var choices := _resolutions_fitting(screen)
	var best: Vector2i = choices[0]
	var best_area := -1
	for choice in choices:
		var area: int = int(choice.x) * int(choice.y)
		if area > best_area:
			best = choice
			best_area = area
	return best


## 3D render scale and MSAA on the root viewport. 2D (HUD, menus) stays at the window resolution.
## Skip writes that already match: assigning msaa_3d on a live Vulkan viewport can SIGSEGV.
func apply_render() -> void:
	if not is_inside_tree() or display_headless():
		return
	var root := get_tree().root
	if root.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if not is_equal_approx(root.scaling_3d_scale, render_scale):
		root.scaling_3d_scale = render_scale
	var want_msaa := msaa as Viewport.MSAA
	if root.msaa_3d != want_msaa:
		root.msaa_3d = want_msaa


func _snap_fps(v: int) -> int:
	v = clampi(v, 0, FPS_CAP_MAX)
	return int(round(float(v) / 10.0)) * 10


func _snap_scale(v: float) -> float:
	return clampf(round(clampf(v, 0.5, 1.0) * 20.0) / 20.0, 0.5, 1.0)


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
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("reload", KEY_R)
	_key("switch_weapon", KEY_Q)
	_key("weapon_1", KEY_1)
	_key("weapon_2", KEY_2)
	_key("weapon_3", KEY_3)
	_key("weapon_4", KEY_4)
	_key("use_streak", KEY_ENTER) # not ui_accept: that one includes Space (jump)
	_key("use_streak", KEY_KP_ENTER)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("zoom", MOUSE_BUTTON_RIGHT)
	_key("toggle_mouse", KEY_ESCAPE)
	_key("chat", KEY_T)
	_key("grenade", KEY_G)
	_key("throw_knife", KEY_F)
	_key("melee", KEY_E)
	_key("sprint", KEY_SHIFT)
	_key("crouch", KEY_CTRL)
	_key("crouch", KEY_C)


func _key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if _has_key(action, keycode):
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if _has_mouse(action, button):
		return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _has_key(action: String, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _has_mouse(action: String, button: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button:
			return true
	return false


## Engine.time_scale is global: on a listen server it would slow bots, timers, and physics for everyone.
func hitstop(seconds: float = 0.05, scale: float = 0.22) -> void:
	if _hitstopping or (is_networked() and multiplayer.is_server()):
		return
	_hitstopping = true
	Engine.time_scale = scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstopping = false
