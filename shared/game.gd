extends Node

## Autoload. Input binds, hit-stop, net combat, and match-wide signals.

signal hit_confirmed(killed: bool, headshot: bool)
signal local_player_ready(player: Player)

const DEFAULT_PORT := 7777
const SHOT_MASK := 1 | 2 | 4
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
	if id <= 0:
		id = p._owner_peer()
	if not net_hp.has(id):
		net_hp[id] = Player.MAX_HP
	return float(net_hp[id])


func set_hp(p: Player, value: float) -> void:
	p.hp = value
	if is_networked() and p.peer_id > 0:
		net_hp[p.peer_id] = value


func clear_peer_hp(peer_id: int) -> void:
	net_hp.erase(peer_id)
	pending_names.erase(peer_id)


func weapon_def(weapon_id: StringName) -> WeaponDef:
	return WEAPON_DEFS.get(weapon_id) as WeaponDef


@rpc("any_peer", "reliable")
func request_weapon_fire(origin: Vector3, look_dir: Vector3, weapon_id: StringName) -> void:
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
	if collider is Player:
		var victim := collider as Player
		if victim == shooter or victim.is_dead:
			return {}
		return victim.apply_hit(hit.position, hit.normal, damage)
	if collider.is_in_group("hurtbox"):
		var dummy := collider.get_parent() as DummyTarget
		if dummy == null:
			return {}
		return dummy.apply_hit(collider, hit.position, hit.normal, damage, hs_mult)
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
	if p:
		p.set_display_name(n)


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
