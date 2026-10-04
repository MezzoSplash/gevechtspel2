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

const DEFAULT_PORT := 7777
const SHOT_MASK := 1 | 2 | 4 # world | players | leftover dummy layer
const WIN_KILLS := 25
const TEAM_SIZE := 5
const TEAM_A := 0
const TEAM_B := 1
const TEAM_NAMES := ["BLUE", "ORANGE"]
## Match modes. Team ids stay in FFA (bot fill/balancing), but nobody is a teammate: use is_enemy().
const MODE_TDM := 0
const MODE_FFA := 1
const MODE_IDS := ["tdm", "ffa"]
const MODE_NAMES := ["Team Deathmatch", "Free For All"]
const FFA_WIN_KILLS := 20
const MOUSE_SENS_MIN := 0.1
const MOUSE_SENS_MAX := 4.0
const ADS_SENS_MIN := 0.1
const ADS_SENS_MAX := 1.5
const ROUND_TIME := 600.0
const WARMUP_TIME := 5.0
const ROUND_END_TIME := 5.0
const INTERMISSION_TIME := 10.0
const FREEZE_TIME := 3.0
const NAME_MAX := 24
## Checked in the ENet auth step (main.gd). Bump with each release that changes RPCs or sync,
## so old clients get a clear "version mismatch" instead of silently broken RPCs.
const NET_VERSION := "0.2.17"
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
}

var is_offline := true
var is_dedicated := false
var chat_open := false # T-chat: blocks move/look/fire until Enter/Esc
var pause_open := false
var in_lobby := false
var round_frozen := false # look OK, no walk/shoot; bots idle
var killcam_active := false # final killcam: no walk/look/shoot/damage; bots idle (Killcam.sync_lock)
var final_kill: Dictionary = {} # match authority: last real kill of this round, replayed by the killcam
var best_trick: Dictionary = {} # match authority: this round's highest-scoring trickshot (same keys + tags/pts/trick_id)
var _shot_ctx: Dictionary = {} # match authority, while a shot resolves: {shooter, origin, scoped}
var _style_chain: Dictionary = {} # peer_id -> [trick kills in a row, time of the last one]
var _bursts: Dictionary = {} # peer_id -> {seq, t, victims}: the rifle burst (held trigger) in progress
var _shotgun_kill_t: Dictionary = {} # peer_id -> time of their last shotgun kill (DOUBLE)
var _hs_streak: Dictionary = {} # peer_id -> rifle headshot kills in a row (HEADSHOT STREAK)
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
## main.gd: Callable(Player) -> Transform3D. Every respawn asks it (FFA: spot farthest from enemies).
var spawn_picker: Callable
## main.gd: Callable(map_id, mode) -> void. Clients load the server's map before their pawn spawns.
var match_config_handler: Callable
var lobby: Dictionary = {} # peer_id → {name, team}
var master_vol := 1.0
var sfx_vol := 1.0
var player_name := "Player"
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
	return FFA_WIN_KILLS if is_ffa() else WIN_KILLS


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


## Server → one client (join) or everyone: which map and mode this server runs.
@rpc("authority", "reliable")
func sync_match_config(new_map: String, new_mode: int) -> void:
	if multiplayer.is_server():
		return
	set_match_config(StringName(new_map), new_mode)


func set_match_config(new_map: StringName, new_mode: int) -> void:
	map_id = new_map if Maps.has(new_map) else Maps.DEFAULT
	mode = clampi(new_mode, MODE_TDM, MODE_FFA)
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
	streaks.erase(peer_id)
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
	burst: int = 0
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
	var mult := clampf(spread_mult, shooter.min_spread_multiplier(), SPREAD_MAX)
	var best := _resolve_weapon_fire(shooter, origin, look_dir, def, mult, shot_seed, scoped, burst)
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


## Host / offline / bots: resolve hits on this machine (must be match authority).
func fire_weapon_locally(
	shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float = 1.0,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0
) -> Dictionary:
	return _resolve_weapon_fire(shooter, origin, look_dir, def, spread_mult, shot_seed, scoped, burst)


## `shot_seed` drives the pellet spread, so Weapon._simulate_pellets_fx draws the same rays.
## Teammates are excluded: shots pass through friends instead of being soaked up by them.
## `scoped`: the shooter had the sniper scope up (only matters for the NOSCOPE trick, never for damage).
## `burst`: the shooter's held-trigger counter for automatic guns (SPRAY TRANSFER only; 0 = unknown).
func _resolve_weapon_fire(
	shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0
) -> Dictionary:
	_shot_ctx = {"shooter": shooter, "origin": origin, "scoped": scoped, "burst": _burst_for(shooter, def, burst)}
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


## Own grenade: kill feed shows it, the streak resets, but no kill for you or your team.
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


const STREAK_AT := 3
const RADAR_TIME := 4.0

var streaks: Dictionary = {}


## Humans only. Death clears the victim. At 3 the radar is armed; Enter turns it on for the whole team.
func _bump_streak(killer_peer_id: int, victim_peer_id: int) -> void:
	if victim_peer_id > 0:
		streaks[victim_peer_id] = 0
		_push_streak(victim_peer_id, 0)
	if killer_peer_id <= 0:
		return
	var n := int(streaks.get(killer_peer_id, 0))
	if n < STREAK_AT:
		n += 1
	streaks[killer_peer_id] = n
	_push_streak(killer_peer_id, n)


func _push_streak(peer_id: int, n: int) -> void:
	if not is_networked() or peer_id == multiplayer.get_unique_id():
		_apply_streak_local(n)
		return
	sync_streak.rpc_id(peer_id, n)


@rpc("authority", "reliable")
func sync_streak(n: int) -> void:
	_apply_streak_local(n)


func _apply_streak_local(n: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_streak(n)


## Slot 0 is the radar. Other slots are reserved until more streaks exist.
## Only slot 0 is wired. A charge is spent even if the radar is already running (time is not stacked).
## Not during the round-start freeze or the killcam: the charge is kept.
func try_activate_streak(peer_id: int, slot: int) -> void:
	if not _is_match_authority():
		return
	if slot != 0 or play_locked():
		return
	if int(streaks.get(peer_id, 0)) < STREAK_AT:
		return
	streaks[peer_id] = 0
	_push_streak(peer_id, 0)
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
		hud.show_radar_event(by_name, team, friendly, by_peer == multiplayer.get_unique_id())


## Round end, round start, killcam, and leaving: no markers carry over.
func clear_radar() -> void:
	radar_left = 0.0
	radar_team = -1
	radar_peer = 0
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.clear_radar()


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
	_round_timer = ROUND_TIME - time_left
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
	if get_team_kills(team_id) >= WIN_KILLS:
		_end_round_team(team_id)


## FFA: first player to FFA_WIN_KILLS wins the round.
func _check_win_player(peer_id: int) -> void:
	if not _round_active or not scores.has(peer_id):
		return
	if int(scores[peer_id].kills) >= FFA_WIN_KILLS:
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
	_bursts.clear()
	_shotgun_kill_t.clear()
	_hs_streak.clear()
	team_kills = [0, 0]
	if is_networked() and multiplayer.is_server():
		sync_team_kills.rpc(0, 0)
	for id in scores:
		scores[id].style = 0
		_apply_score(id, 0, str(scores[id].name), int(scores[id].get("team", 0)))
		if is_networked() and multiplayer.is_server():
			sync_score.rpc(id, 0, str(scores[id].name), int(scores[id].team), 0)


func end_freeze() -> void:
	_round_active = true
	_round_timer = 0.0
	set_round_frozen(false)
	if is_networked() and multiplayer.is_server():
		sync_round_time.rpc(ROUND_TIME)


## Late joiner: scores, team totals, freeze, and clock, so the HUD is right from the first frame.
func send_match_state(peer_id: int) -> void:
	if not is_networked() or not multiplayer.is_server():
		return
	sync_match_config.rpc_id(peer_id, String(map_id), mode)
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
	streaks.clear()
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
	_bursts.clear()
	_shotgun_kill_t.clear()
	_hs_streak.clear()
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


func update_round_timer(delta: float) -> bool:
	if not _round_active:
		return false
	_round_timer += delta
	if _round_timer >= ROUND_TIME:
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
	return maxf(ROUND_TIME - _round_timer, 0.0)


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


## Listen-server: bots have MultiplayerSynchronizer off, so we push poses ourselves.
func _physics_process(delta: float) -> void:
	_tick_regen(delta)
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


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		master_vol = clampf(float(cfg.get_value("audio", "master", 1.0)), 0.0, 1.0)
		sfx_vol = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
		mouse_sens = clampf(float(cfg.get_value("input", "mouse_sens", 1.0)), MOUSE_SENS_MIN, MOUSE_SENS_MAX)
		ads_sens = clampf(float(cfg.get_value("input", "ads_sens", 0.45)), ADS_SENS_MIN, ADS_SENS_MAX)
		var m := StringName(str(cfg.get_value("match", "map", String(Maps.DEFAULT))))
		last_map = m if Maps.has(m) else Maps.DEFAULT
		last_mode = clampi(int(cfg.get_value("match", "mode", MODE_TDM)), MODE_TDM, MODE_FFA)
	apply_audio()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_vol)
	cfg.set_value("audio", "sfx", sfx_vol)
	cfg.set_value("input", "mouse_sens", mouse_sens)
	cfg.set_value("input", "ads_sens", ads_sens)
	cfg.set_value("match", "map", String(last_map))
	cfg.set_value("match", "mode", last_mode)
	cfg.save("user://settings.cfg")


func set_mouse_sens(v: float) -> void:
	mouse_sens = clampf(v, MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	save_settings()


func set_ads_sens(v: float) -> void:
	ads_sens = clampf(v, ADS_SENS_MIN, ADS_SENS_MAX)
	save_settings()


## Menu choice for solo/host, remembered for next time.
func remember_match_choice(m: StringName, md: int) -> void:
	last_map = m
	last_mode = md
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
