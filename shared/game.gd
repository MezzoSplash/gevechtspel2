extends Node
## Autoload `Game`. Shared weapon stats, server-authoritative hits, scores, and LAN RPCs.
## Clients never decide damage, deaths, or bot actions.

signal hit_confirmed(killed: bool, headshot: bool)
signal local_player_ready(player: Player)
signal score_changed(peer_id: int, score: int, name: String)
signal round_ended(winner_peer_id: int, winner_name: String, scores: Dictionary)
signal kill_feed(killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int)
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
const ROUND_TIME := 600.0
const WARMUP_TIME := 5.0
const ROUND_END_TIME := 5.0
const INTERMISSION_TIME := 10.0
const FREEZE_TIME := 3.0
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
var lobby: Dictionary = {} # peer_id → {name, team}
var master_vol := 1.0
var sfx_vol := 1.0
var player_name := "Player"
var preferred_team := 0 # 0 Blue, 1 Orange — chosen in the menu
var pending_names: Dictionary = {} # peer_id → name, filled before spawn if the client RPCs first
var pending_teams: Dictionary = {} # peer_id → team, from join RPC
var net_hp: Dictionary = {} # server copy of HP, keyed by peer_id (bots included)
var _hitstopping := false
var _round_music: AudioStreamPlayer

var scores: Dictionary = {}
var pings: Dictionary = {}
var _ping_accum := 0.0
var _round_timer := 0.0
var _round_active := false
var _match_state := 0
var _state_timer := 0.0


func is_networked() -> bool:
	return not is_offline


func rpc_from_server() -> bool:
	if is_offline:
		return true
	var id := multiplayer.get_remote_sender_id()
	return id == 1 or id == 0


## Humans are named by peer id; bots are `bot1` with peer_id -1, etc.
func player_for_peer(peer_id: int) -> Player:
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null:
			continue
		if p.peer_id == peer_id or str(n.name) == str(peer_id):
			return p
		if p.is_bot and str(n.name) == "bot%d" % abs(peer_id):
			p.peer_id = peer_id
			return p
	return null


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


func clear_peer_hp(peer_id: int) -> void:
	net_hp.erase(peer_id)
	pending_names.erase(peer_id)
	scores.erase(peer_id)


func weapon_def(weapon_id: StringName) -> WeaponDef:
	return WEAPON_DEFS.get(weapon_id) as WeaponDef


## Client → server fire. Hits resolve here; tracers/sfx go back out via broadcast_shot_fx.
@rpc("any_peer", "reliable")
func request_weapon_fire(origin: Vector3, look_dir: Vector3, weapon_id: StringName, muzzle_pos: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var shooter := player_for_peer(peer)
	if shooter == null or shooter.is_dead:
		return
	var def := weapon_def(weapon_id)
	if def == null:
		return
	var from := muzzle_pos if muzzle_pos != Vector3.ZERO else origin
	broadcast_shot_fx(from, origin + look_dir.normalized() * def.range_m, peer)
	var best := _resolve_weapon_fire(shooter, origin, look_dir, def, 1.0)
	if best.get("hit", false):
		notify_hit.rpc_id(peer, best.killed, best.headshot)


## Host / offline / bots: resolve hits on this machine (must be match authority).
func fire_weapon_locally(
	shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float = 1.0
) -> Dictionary:
	return _resolve_weapon_fire(shooter, origin, look_dir, def, spread_mult)


func _resolve_weapon_fire(
	shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float
) -> Dictionary:
	look_dir = look_dir.normalized()
	var spread := def.spread_deg * spread_mult
	var best := {"killed": false, "headshot": false, "hit": false}
	var space := shooter.get_world_3d().direct_space_state
	for _i in def.pellet_count:
		var dir := _spread_dir(look_dir, spread)
		var to := origin + dir * def.range_m
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.collision_mask = SHOT_MASK
		query.exclude = [shooter.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var dist := origin.distance_to(hit.position)
		var dmg := def.damage_at_distance(dist)
		var result := _apply_shot_hit(shooter, hit, dmg, def.headshot_multiplier)
		if result.is_empty():
			continue
		best = _merge_hit_result(best, result)
	return best


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


func _spread_dir(forward: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return forward.normalized()
	var rad := deg_to_rad(deg)
	var theta := randf() * TAU
	var phi := rad * sqrt(randf())
	var up := Vector3.UP
	var right := forward.cross(up)
	if right.length_squared() < 0.001:
		right = forward.cross(Vector3.RIGHT)
	right = right.normalized()
	up = right.cross(forward).normalized()
	return (forward.normalized() * cos(phi) + (right * cos(theta) + up * sin(theta)) * sin(phi)).normalized()


func _apply_shot_hit(shooter: Player, hit: Dictionary, damage: float, hs_mult: float) -> Dictionary:
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
		if victim.team_id == shooter.team_id:
			return {}
		return victim.apply_hit(hit.position, hit.normal, damage, true, killer_id, shooter.weapon.def.id if shooter.weapon and shooter.weapon.def else &"rifle")
	return {}


@rpc("authority", "reliable")
func notify_hit(killed: bool, headshot: bool) -> void:
	hit_confirmed.emit(killed, headshot)


@rpc("any_peer", "reliable")
func submit_display_name(n: String, team: int = -1) -> void:
	if not multiplayer.is_server():
		return
	n = n.strip_edges()
	if n == "":
		n = "Player"
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


## Also writes the scoreboard name. Spawn often happens before the client's name RPC.
@rpc("authority", "call_local", "reliable")
func apply_display_name(peer_id: int, n: String) -> void:
	var p := player_for_peer(peer_id)
	var team := 0
	var kills := 0
	if p:
		p.set_display_name(n)
		team = p.team_id
	if scores.has(peer_id):
		kills = int(scores[peer_id].kills)
		team = int(scores[peer_id].get("team", team))
	_apply_score(peer_id, kills, n, team)


@rpc("authority", "call_local", "reliable")
func broadcast_hurt(peer_id: int, new_hp: float, killed: bool) -> void:
	var p := player_for_peer(peer_id)
	if p:
		p.apply_hurt_state(new_hp, killed)


@rpc("authority", "call_local", "reliable")
func broadcast_respawn(peer_id: int) -> void:
	var p := player_for_peer(peer_id)
	if p:
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
		scores[peer_id] = {"name": n, "kills": 0, "team": team}
	scores[peer_id].kills = kills
	scores[peer_id].name = n
	scores[peer_id].team = team
	score_changed.emit(peer_id, kills, n)


func register_participant(peer_id: int, n: String, team: int = 0) -> void:
	if scores.has(peer_id):
		var existing: String = str(scores[peer_id].name)
		var incoming_placeholder := n == "" or n == "Player"
		var keep_existing := existing != "" and existing != "Player"
		if incoming_placeholder and keep_existing:
			if int(scores[peer_id].get("team", team)) != team:
				_apply_score(peer_id, int(scores[peer_id].kills), existing, team)
			return
		if n != "" and existing != n:
			_apply_score(peer_id, int(scores[peer_id].kills), n, int(scores[peer_id].get("team", team)))
			if is_networked() and multiplayer.is_server():
				sync_score.rpc(peer_id, int(scores[peer_id].kills), n, int(scores[peer_id].team))
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
func register_kill(killer_peer_id: int, victim_peer_id: int, weapon_id: StringName = &"rifle") -> void:
	if not _is_match_authority():
		return
	if killer_peer_id == 0:
		return
	if not scores.has(killer_peer_id):
		var killer := player_for_peer(killer_peer_id)
		var team := killer.team_id if killer else 0
		register_participant(killer_peer_id, _display_name_for(killer_peer_id), team)
	var kills: int = int(scores[killer_peer_id].kills) + 1
	var n: String = scores[killer_peer_id].name
	var team_id: int = int(scores[killer_peer_id].get("team", 0))
	_apply_score(killer_peer_id, kills, n, team_id)
	if is_networked():
		sync_score.rpc(killer_peer_id, kills, n, team_id)
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
	_emit_kill_feed(killer_name, victim_name, weapon_id, team_id, victim_team)
	if is_networked():
		sync_kill_feed.rpc(killer_name, victim_name, String(weapon_id), team_id, victim_team)
	_check_win_team(team_id)


func _emit_kill_feed(killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int) -> void:
	kill_feed.emit(killer_name, victim_name, weapon_id, killer_team, victim_team)


@rpc("authority", "reliable")
func sync_kill_feed(killer_name: String, victim_name: String, weapon_id: String, killer_team: int, victim_team: int) -> void:
	if multiplayer.is_server():
		return
	kill_feed.emit(killer_name, victim_name, StringName(weapon_id), killer_team, victim_team)


@rpc("any_peer", "reliable")
func report_death(killer_peer_id: int, victim_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	register_kill(killer_peer_id, victim_peer_id)


@rpc("authority", "reliable")
func sync_score(peer_id: int, score: int, n: String, team: int = 0) -> void:
	_apply_score(peer_id, score, n, team)


@rpc("authority", "reliable")
func sync_round_end(winner_peer_id: int, winner_name: String, round_scores: Dictionary) -> void:
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


func _check_win_team(team_id: int) -> void:
	if not _round_active:
		return
	if get_team_kills(team_id) >= WIN_KILLS:
		_end_round_team(team_id)


func _end_round(winner_peer_id: int) -> void:
	var team := 0
	if scores.has(winner_peer_id):
		team = int(scores[winner_peer_id].get("team", 0))
	_end_round_team(team)


func _end_round_team(team_id: int) -> void:
	_round_active = false
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
	for id in scores:
		_apply_score(id, 0, str(scores[id].name), int(scores[id].get("team", 0)))
		if is_networked() and multiplayer.is_server():
			sync_score.rpc(id, 0, str(scores[id].name), int(scores[id].team))


func end_freeze() -> void:
	_round_active = true
	_round_timer = 0.0
	set_round_frozen(false)


func update_round_timer(delta: float) -> bool:
	if not _round_active:
		return false
	_round_timer += delta
	if _round_timer >= ROUND_TIME:
		_end_round_team(_get_leader())
		return true
	return false


func _get_leader() -> int:
	if get_team_kills(TEAM_A) >= get_team_kills(TEAM_B):
		return TEAM_A
	return TEAM_B


func get_team_kills(team_id: int) -> int:
	var total := 0
	for id in scores:
		if int(scores[id].get("team", 0)) == team_id:
			total += int(scores[id].kills)
	return total


func get_scores() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in scores:
		out.append({
			"peer_id": id,
			"name": scores[id].name,
			"kills": scores[id].kills,
			"team": int(scores[id].get("team", 0)),
			"ping": int(pings.get(id, -1)),
		})
	out.sort_custom(_sort_scores)
	return out


func _sort_scores(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("team", 0)) != int(b.get("team", 0)):
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


func _spawn_net_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
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


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		master_vol = clampf(float(cfg.get_value("audio", "master", 1.0)), 0.0, 1.0)
		sfx_vol = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
	apply_audio()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_vol)
	cfg.set_value("audio", "sfx", sfx_vol)
	cfg.save("user://settings.cfg")


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
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("zoom", MOUSE_BUTTON_RIGHT)
	_key("toggle_mouse", KEY_ESCAPE)
	_key("chat", KEY_T)
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


func hitstop(seconds: float = 0.05, scale: float = 0.22) -> void:
	if _hitstopping:
		return
	_hitstopping = true
	Engine.time_scale = scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstopping = false
