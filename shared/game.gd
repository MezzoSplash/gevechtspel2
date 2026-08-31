extends Node

## Autoload. Input binds, hit-stop, net combat, and match-wide signals.

signal hit_confirmed(killed: bool, headshot: bool)
signal local_player_ready(player: Player)

const DEFAULT_PORT := 7777
const SHOT_MASK := 1 | 2 | 4

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


@rpc("any_peer", "reliable")
func request_shot(origin: Vector3, dir: Vector3, range_m: float, damage: float, hs_mult: float) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var shooter := player_for_peer(peer)
	if shooter == null or shooter.is_dead:
		return
	dir = dir.normalized()
	var to := origin + dir * range_m
	var space := shooter.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = SHOT_MASK
	query.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var result := _apply_shot_hit(shooter, hit, damage, hs_mult)
	if result.is_empty():
		return
	notify_hit.rpc_id(peer, result.killed, result.headshot)


func apply_shot_locally(shooter: Player, hit: Dictionary, damage: float, hs_mult: float) -> Dictionary:
	return _apply_shot_hit(shooter, hit, damage, hs_mult)


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
