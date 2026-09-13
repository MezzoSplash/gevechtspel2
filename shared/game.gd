extends Node

## Autoload. Input binds, hit-stop, net combat, and match-wide signals.

signal hit_confirmed(killed: bool, headshot: bool)
signal local_player_ready(player: Player)
signal score_changed(peer_id: int, score: int, name: String)
signal round_ended(winner_peer_id: int, winner_name: String, scores: Dictionary)

const DEFAULT_PORT := 7777
const SHOT_MASK := 1 | 2 | 4
const WIN_KILLS := 25
const TEAM_SIZE := 5
const TEAM_A := 0
const TEAM_B := 1
const TEAM_NAMES := ["BLUE", "ORANGE"]
const ROUND_TIME := 600.0
const WARMUP_TIME := 5.0
const ROUND_END_TIME := 5.0
const INTERMISSION_TIME := 10.0
const WEAPON_DEFS := {
	&"rifle": preload("res://data/weapons/rifle.tres"),
	&"pistol": preload("res://data/weapons/pistol.tres"),
	&"shotgun": preload("res://data/weapons/shotgun.tres"),
}

var is_offline := true
var is_dedicated := false
var player_name := "Player"
var pending_names: Dictionary = {}
var net_hp: Dictionary = {}
var _hitstopping := false

var scores: Dictionary = {}
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


func player_for_peer(peer_id: int) -> Player:
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null:
			continue
		if p.peer_id == peer_id or str(n.name) == str(peer_id):
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
		return victim.apply_hit(hit.position, hit.normal, damage, true, killer_id)
	return {}


@rpc("authority", "reliable")
func notify_hit(killed: bool, headshot: bool) -> void:
	hit_confirmed.emit(killed, headshot)


@rpc("any_peer", "reliable")
func submit_display_name(n: String) -> void:
	if not multiplayer.is_server():
		return
	n = n.strip_edges()
	if n == "":
		n = "Player"
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	pending_names[peer] = n
	apply_display_name.rpc(peer, n)


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


func register_kill(killer_peer_id: int, _victim_peer_id: int) -> void:
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
	_check_win_team(team_id)


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


func start_round() -> void:
	_round_timer = 0.0
	_round_active = true
	for id in scores:
		_apply_score(id, 0, str(scores[id].name), int(scores[id].get("team", 0)))
		if is_networked() and multiplayer.is_server():
			sync_score.rpc(id, 0, str(scores[id].name), int(scores[id].team))


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


func broadcast_shot_fx(from: Vector3, to: Vector3, shooter_peer_id: int) -> void:
	if not is_networked() or not multiplayer.is_server():
		return
	if shooter_peer_id > 0 and shooter_peer_id != multiplayer.get_unique_id():
		_spawn_net_tracer(from, to)
	sync_shot_fx.rpc(from, to, shooter_peer_id)


@rpc("authority", "unreliable")
func sync_shot_fx(from: Vector3, to: Vector3, shooter_peer_id: int = 0) -> void:
	if shooter_peer_id != 0 and shooter_peer_id == multiplayer.get_unique_id():
		return
	_spawn_net_tracer(from, to)


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


func _physics_process(_delta: float) -> void:
	if not is_networked() or not multiplayer.is_server():
		return
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
	_bind_inputs()


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
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_key("toggle_mouse", KEY_ESCAPE)
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
