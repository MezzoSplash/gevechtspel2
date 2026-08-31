class_name DummyTarget
extends Node3D

const MAX_HP := 100.0
const RESPAWN := 1.4
const FIRE_RATE := 1.0
const DAMAGE := 12.0
const SPREAD_DEG := 3.4
const RANGE_M := 80.0
const ACQUIRE := 0.22
const SHOT_MASK := 1 | 2

@onready var body: StaticBody3D = $Body
@onready var head: StaticBody3D = $Head
@onready var body_mesh: MeshInstance3D = $Body/Mesh
@onready var head_mesh: MeshInstance3D = $Head/Mesh
@onready var body_col: CollisionShape3D = $Body/CollisionShape3D
@onready var head_col: CollisionShape3D = $Head/CollisionShape3D
@onready var muzzle: Marker3D = $Muzzle
@onready var fire_sfx: AudioStreamPlayer3D = $FireSfx

var hp := MAX_HP
var _dead := false
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _flash := 0.0
var _cooldown := 0.0
var _acquire_left := ACQUIRE


func _ready() -> void:
	body.add_to_group("hurtbox")
	head.add_to_group("hurtbox")
	_body_mat = _dup_mat(body_mesh)
	_head_mat = _dup_mat(head_mesh)
	_cooldown = randf_range(0.3, 1.1)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		var glow := _flash
		_body_mat.emission_energy_multiplier = glow * 4.0
		_head_mat.emission_energy_multiplier = glow * 5.0
		_body_mat.emission = Color(1.0, 0.35, 0.15)
		_head_mat.emission = Color(1.0, 0.6, 0.25)


func _physics_process(delta: float) -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _dead:
		return
	var player := _closest_player()
	if player == null:
		_acquire_left = ACQUIRE
		return
	if not _can_see(player):
		_acquire_left = ACQUIRE
		return
	_acquire_left = maxf(_acquire_left - delta, 0.0)
	if _acquire_left > 0.0 or _cooldown > 0.0:
		return
	_shoot(player)


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


func apply_hit(part: Node, point: Vector3, _normal: Vector3, base_damage: float, headshot_mult: float) -> Dictionary:
	if _dead:
		return {"killed": false, "headshot": false, "damage": 0}
	if Game.is_networked() and not multiplayer.is_server():
		return {"killed": false, "headshot": false, "damage": 0}
	var is_head := part == head
	var dmg := roundi(base_damage * (headshot_mult if is_head else 1.0))
	var was_alive := hp > 0.0
	hp -= float(dmg)
	var killed := was_alive and hp <= 0.0
	if Game.is_networked():
		_net_hit.rpc(dmg, point, is_head, killed)
	else:
		_show_hit(dmg, point, is_head, killed)
	if killed:
		_die()
	return {"killed": killed, "headshot": is_head, "damage": dmg}


@rpc("authority", "call_local", "reliable")
func _net_hit(dmg: int, point: Vector3, is_head: bool, killed: bool) -> void:
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
	query.exclude = [body.get_rid(), head.get_rid()]
	var hit := space.intersect_ray(query)
	return hit.has("collider") and hit.collider == player


func _shoot(player: Player) -> void:
	_cooldown = 1.0 / FIRE_RATE + randf_range(0.0, 0.12)
	var from := muzzle.global_position
	var aim := (_aim_point(player) - from).normalized()
	var dir := _spread(aim, SPREAD_DEG)
	var to := from + dir * RANGE_M
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = SHOT_MASK
	query.exclude = [body.get_rid(), head.get_rid()]
	var hit := space.intersect_ray(query)
	var end := to
	if hit:
		end = hit.position
		var collider := hit.collider as Node
		if collider == player:
			player.apply_hit(hit.position, hit.normal, DAMAGE, false)
	if Game.is_networked():
		_net_shot.rpc(from, end)
	else:
		_fx_shot(from, end)


@rpc("authority", "call_local", "unreliable")
func _net_shot(from: Vector3, to: Vector3) -> void:
	_fx_shot(from, to)


func _fx_shot(from: Vector3, to: Vector3) -> void:
	if fire_sfx.stream:
		fire_sfx.pitch_scale = randf_range(0.94, 1.06)
		fire_sfx.play()
	_spawn_tracer(from, to)


func _die() -> void:
	_dead = true
	if Game.is_networked() and not multiplayer.is_server():
		return
	get_tree().create_timer(RESPAWN).timeout.connect(_respawn)


func _apply_dead_visual() -> void:
	body_mesh.visible = false
	head_mesh.visible = false
	body_col.disabled = true
	head_col.disabled = true


func _apply_alive_visual() -> void:
	body_mesh.visible = true
	head_mesh.visible = true
	body_col.disabled = false
	head_col.disabled = false
	_flash = 0.0


func _respawn() -> void:
	hp = MAX_HP
	_dead = false
	_acquire_left = ACQUIRE
	_cooldown = randf_range(0.2, 0.8)
	if Game.is_networked():
		_net_alive.rpc()
	else:
		_apply_alive_visual()


@rpc("authority", "call_local", "reliable")
func _net_alive() -> void:
	_dead = false
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
