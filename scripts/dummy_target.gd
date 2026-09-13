class_name DummyTarget
extends CharacterBody3D

const MAX_HP := 100.0
const RESPAWN := 1.6
const FIRE_RATE := 1.0
const DAMAGE := 12.0
const SPREAD_DEG := 4.0
const RANGE_M := 80.0
const ACQUIRE := 0.22
const SHOT_MASK := 1 | 2
const MOVE_SPEED := 4.4
const STRAFE_SPEED := 3.4
const FIGHT_RANGE := 9.0
const TOO_CLOSE := 3.6

@onready var col: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: MeshInstance3D = $Body
@onready var head: StaticBody3D = $Head
@onready var head_mesh: MeshInstance3D = $Head/Mesh
@onready var head_col: CollisionShape3D = $Head/CollisionShape3D
@onready var muzzle: Marker3D = $Muzzle
@onready var fire_sfx: AudioStreamPlayer3D = $FireSfx
@onready var agent: NavigationAgent3D = $NavigationAgent3D

var hp := MAX_HP
var _dead := false
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _flash := 0.0
var _cooldown := 0.0
var _acquire_left := ACQUIRE
var _home := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _strafe_t := 0.0
var _strafe_sign := 1.0
var _repath_t := 0.0
@export var peer_id := 0


func _enter_tree() -> void:
	if Game.is_networked():
		set_multiplayer_authority(1, true)


func _ready() -> void:
	add_to_group("dummy")
	head.add_to_group("hurtbox")
	_body_mat = _dup_mat(body_mesh)
	_head_mat = _dup_mat(head_mesh)
	_home = global_position
	_last_seen = global_position
	_cooldown = randf_range(0.3, 1.1)
	_strafe_sign = -1.0 if randf() < 0.5 else 1.0
	floor_snap_length = 0.2
	if has_node("Sync"):
		$Sync.public_visibility = false
	if Game.is_networked() and not multiplayer.is_server():
		set_physics_process(false)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		_body_mat.emission_energy_multiplier = _flash * 4.0
		_head_mat.emission_energy_multiplier = _flash * 5.0
		_body_mat.emission = Color(1.0, 0.35, 0.15)
		_head_mat.emission = Color(1.0, 0.6, 0.25)


func _physics_process(delta: float) -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _dead:
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y += float(get_gravity().y) * delta
	else:
		velocity.y = 0.0
	var player := _closest_player()
	if player == null:
		_acquire_left = ACQUIRE
		_move_to(_home, MOVE_SPEED)
		_broadcast_pose()
		return
	if _can_see(player):
		_last_seen = player.global_position
		_acquire_left = maxf(_acquire_left - delta, 0.0)
		_fight(player, delta)
	else:
		_acquire_left = ACQUIRE
		_hunt(player, delta)
	move_and_slide()
	_broadcast_pose()


func _hunt(player: Player, delta: float) -> void:
	_repath_t -= delta
	var dest := player.global_position
	dest.y = global_position.y
	if _repath_t <= 0.0:
		agent.target_position = dest
		_repath_t = 0.25
	_follow_agent(MOVE_SPEED, dest)


func _fight(player: Player, delta: float) -> void:
	_face(player)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_sign *= -1.0
		_strafe_t = randf_range(0.65, 1.35)
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = transform.basis.z
	away = away.normalized()
	var side := Vector3.UP.cross(away).normalized() * _strafe_sign
	var dist := global_position.distance_to(player.global_position)
	var dest := global_position + side * 2.4
	if dist < TOO_CLOSE:
		dest += away * 3.2
	elif dist > FIGHT_RANGE:
		dest += -away * 2.6
	_repath_t -= delta
	if _repath_t <= 0.0:
		agent.target_position = dest
		_repath_t = 0.18
	_follow_agent(STRAFE_SPEED, dest)
	if _acquire_left <= 0.0 and _cooldown <= 0.0:
		_shoot(player)


func _follow_agent(speed: float, dest: Vector3 = Vector3.INF) -> void:
	if not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0.0
		if dir.length() >= 0.08:
			dir = dir.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			return
	if dest != Vector3.INF:
		var straight := dest - global_position
		straight.y = 0.0
		if straight.length() >= 0.12:
			straight = straight.normalized()
			velocity.x = straight.x * speed
			velocity.z = straight.z * speed
			return
	velocity.x = move_toward(velocity.x, 0.0, speed)
	velocity.z = move_toward(velocity.z, 0.0, speed)


func _move_to(dest: Vector3, speed: float) -> void:
	agent.target_position = dest
	_follow_agent(speed, dest)
	move_and_slide()


func _broadcast_pose() -> void:
	if Game.is_networked() and multiplayer.is_server():
		Game.sync_dummy_pose.rpc(str(name), global_position, rotation.y)


func apply_network_pose(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO


func _face(player: Player) -> void:
	var look := player.global_position
	look.y = global_position.y
	if look.distance_squared_to(global_position) > 0.04:
		look_at(look, Vector3.UP)


func apply_hit(part: Node, point: Vector3, _normal: Vector3, base_damage: float, headshot_mult: float, killer_peer_id: int = 0) -> Dictionary:
	if _dead:
		return {"killed": false, "headshot": false, "damage": 0}
	if Game.is_networked() and not multiplayer.is_server():
		return {"killed": false, "headshot": false, "damage": 0}
	var is_head := part == head or point.y >= global_position.y + 1.35
	var dmg := roundi(base_damage * (headshot_mult if is_head else 1.0))
	var was_alive := hp > 0.0
	hp -= float(dmg)
	var killed := was_alive and hp <= 0.0
	if killed:
		Game.register_kill(killer_peer_id, peer_id)
	_show_hit(dmg, point, is_head, killed)
	if Game.is_networked():
		Game.sync_dummy_hit.rpc(str(name), dmg, point, is_head, killed)
	if killed:
		_die()
	return {"killed": killed, "headshot": is_head, "damage": dmg}


func show_network_hit(dmg: int, point: Vector3, is_head: bool, killed: bool) -> void:
	_show_hit(dmg, point, is_head, killed)


func _show_hit(dmg: int, point: Vector3, is_head: bool, killed: bool) -> void:
	_flash = 1.0
	_spawn_number(dmg, point, is_head)
	if killed:
		_dead = true
		_apply_dead_visual()


func _aim_point(player: Player) -> Vector3:
	return player.global_position + Vector3(0.0, 1.0, 0.0)


func _can_see(player: Player) -> bool:
	var from := muzzle.global_position
	var to := _aim_point(player)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = SHOT_MASK
	query.exclude = [get_rid(), head.get_rid()]
	var hit := space.intersect_ray(query)
	return hit.has("collider") and hit.collider == player


func _closest_player() -> Player:
	var best: Player = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead:
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best


func _shoot(player: Player) -> void:
	_cooldown = 1.0 / FIRE_RATE + randf_range(0.0, 0.12)
	var from := muzzle.global_position
	var aim := (_aim_point(player) - from).normalized()
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	var spread := SPREAD_DEG * (1.45 if moving else 1.0)
	var dir := _spread(aim, spread)
	var to := from + dir * RANGE_M
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = SHOT_MASK
	query.exclude = [get_rid(), head.get_rid()]
	var hit := space.intersect_ray(query)
	var end := to
	if hit:
		end = hit.position
		if hit.collider == player:
			player.apply_hit(hit.position, hit.normal, DAMAGE, false, peer_id)
	_fx_shot(from, end)
	if Game.is_networked():
		Game.sync_dummy_shot.rpc(from, end)


func play_shot_fx(from: Vector3, to: Vector3) -> void:
	_fx_shot(from, to)


func _fx_shot(from: Vector3, to: Vector3) -> void:
	if fire_sfx.stream:
		fire_sfx.pitch_scale = randf_range(0.94, 1.06)
		fire_sfx.play()
	_spawn_tracer(from, to)


func _die() -> void:
	_dead = true
	velocity = Vector3.ZERO
	if Game.is_networked() and not multiplayer.is_server():
		return
	get_tree().create_timer(RESPAWN).timeout.connect(_respawn)


func _apply_dead_visual() -> void:
	body_mesh.visible = false
	head_mesh.visible = false
	col.disabled = true
	head_col.disabled = true


func _apply_alive_visual() -> void:
	body_mesh.visible = true
	head_mesh.visible = true
	col.disabled = false
	head_col.disabled = false
	_flash = 0.0


func _respawn() -> void:
	hp = MAX_HP
	_dead = false
	_acquire_left = ACQUIRE
	_cooldown = randf_range(0.2, 0.8)
	global_position = _home
	velocity = Vector3.ZERO
	_apply_alive_visual()
	if Game.is_networked():
		Game.sync_dummy_alive.rpc(str(name), global_position)
		_broadcast_pose()


func show_network_alive(pos: Vector3) -> void:
	_dead = false
	global_position = pos
	velocity = Vector3.ZERO
	_apply_alive_visual()


func _spread(forward: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return forward.normalized()
	var rad := deg_to_rad(deg)
	var theta := randf() * TAU
	var phi := rad * sqrt(randf())
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = forward.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(forward).normalized()
	return (forward.normalized() * cos(phi) + (right * cos(theta) + up * sin(theta)) * sin(phi)).normalized()


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.1)
	mat.emission_energy_multiplier = 2.6
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(mesh_inst)
	mesh_inst.global_position = (from + to) * 0.5
	if from.distance_squared_to(to) > 0.0001:
		mesh_inst.look_at(to, Vector3.UP)
	get_tree().create_timer(0.055).timeout.connect(mesh_inst.queue_free)


func _spawn_number(amount: int, pos: Vector3, is_head: bool) -> void:
	var lab := Label3D.new()
	lab.text = str(amount)
	lab.font_size = 64 if is_head else 48
	lab.modulate = Color(1.0, 0.78, 0.18) if is_head else Color(1, 1, 1)
	lab.outline_modulate = Color(0, 0, 0, 0.85)
	lab.outline_size = 8
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	get_tree().root.add_child(lab)
	lab.global_position = pos + Vector3(0.0, 0.12, 0.0)
	var tw := lab.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "global_position", lab.global_position + Vector3(0, 0.85, 0), 0.45)
	tw.tween_property(lab, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(lab.queue_free)


func _dup_mat(mesh: MeshInstance3D) -> StandardMaterial3D:
	var src := mesh.get_active_material(0)
	var mat: StandardMaterial3D
	if src is StandardMaterial3D:
		mat = (src as StandardMaterial3D).duplicate()
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.25, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0, 0, 0)
	mat.emission_energy_multiplier = 0.0
	mesh.set_surface_override_material(0, mat)
	return mat
