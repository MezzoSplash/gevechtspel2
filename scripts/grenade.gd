class_name Grenade
extends Node3D
## Server-simulated arc. Clients only follow synced positions.
## Splash ignores teammates. The thrower can still hurt themselves.

const FUSE := 1.2
const THROW_SPEED := 18.0
const RADIUS := 5.5
const MAX_DAMAGE := 140.0
const BOUNCE := 0.42
const MASK := 1 | 2

var thrower_id := 0
var thrower_team := 0
var velocity := Vector3.ZERO
var _fuse := FUSE
var _net_id := 0
var _sync_t := 0.0


static func launch(thrower: Player, origin: Vector3, dir: Vector3) -> void:
	var g := Grenade.new()
	g.thrower_id = thrower.peer_id
	g.thrower_team = thrower.team_id
	g.velocity = dir.normalized() * THROW_SPEED + Vector3.UP * 4.0
	g._net_id = Game.next_grenade_id()
	var root := thrower.get_tree().current_scene
	root.add_child(g)
	g.global_position = origin
	if Game.is_networked():
		Game.sync_grenade_spawn.rpc(g._net_id, origin)


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.45, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.25)
	mat.emission_energy_multiplier = 1.4
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


## Ray-step so it bounces instead of tunneling. Fuse is time, not first impact.
func _physics_process(delta: float) -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	_fuse -= delta
	var grav := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	velocity.y -= grav * delta
	var motion := velocity * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + motion)
	query.collision_mask = MASK
	var hit := space.intersect_ray(query)
	if hit:
		global_position = hit.position + hit.normal * 0.06
		velocity = velocity.bounce(hit.normal) * BOUNCE
	else:
		global_position += motion
	if Game.is_networked():
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = 0.05
			Game.sync_grenade_pose.rpc(_net_id, global_position)
	if _fuse <= 0.0:
		_explode()


## Linear splash to 0 at RADIUS. 140 at the body is a kill; allow_headshot stays off.
func _explode() -> void:
	var pos := global_position
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead:
			continue
		if p != _thrower() and p.team_id == thrower_team:
			continue
		var dist := pos.distance_to(p.global_position + Vector3(0.0, 1.0, 0.0))
		if dist > RADIUS:
			continue
		var dmg := MAX_DAMAGE * (1.0 - dist / RADIUS)
		p.apply_hit(p.global_position + Vector3(0, 1, 0), Vector3.UP, dmg, false, thrower_id, &"grenade")
	if Game.is_networked():
		Game.sync_grenade_boom.rpc(pos, _net_id)
	else:
		Grenade.play_boom(pos)
	queue_free()


func _thrower() -> Player:
	return Game.player_for_peer(thrower_id)


## Local-only FX: flash, light, boom, and outward tracer shards.
static func play_boom(pos: Vector3) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var scene := tree.current_scene
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.12)
	light.light_energy = 16.0
	light.omni_range = 9.0
	scene.add_child(light)
	light.global_position = pos
	var flash := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.35
	ball.height = 0.7
	flash.mesh = ball
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.72, 0.25, 0.85)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.45, 0.1)
	flash_mat.emission_energy_multiplier = 4.0
	flash.material_override = flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(flash)
	flash.global_position = pos
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = load("res://assets/sounds/grenade_boom.wav")
	sfx.bus = "SFX"
	sfx.unit_size = 8.0
	sfx.max_distance = 40.0
	scene.add_child(sfx)
	sfx.global_position = pos
	sfx.play()
	var boom := flash.create_tween()
	boom.set_parallel(true)
	boom.tween_property(flash, "scale", Vector3(7.0, 7.0, 7.0), 0.18)
	boom.tween_property(flash_mat, "albedo_color:a", 0.0, 0.22)
	boom.chain().tween_callback(flash.queue_free)
	var glow := light.create_tween()
	glow.tween_property(light, "light_energy", 0.0, 0.35)
	glow.tween_callback(light.queue_free)
	_spawn_fragments(scene, pos)
	tree.create_timer(1.2).timeout.connect(sfx.queue_free)


## Short streaks, not extra damage. They fade inside the splash radius.
static func _spawn_fragments(scene: Node, pos: Vector3) -> void:
	for i in 18:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.15, 1.0), randf_range(-1.0, 1.0)).normalized()
		var length := randf_range(0.35, 0.9)
		var shard := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.035, 0.035, length)
		shard.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.55, 0.15) if i % 3 != 0 else Color(1.0, 0.9, 0.55)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 3.2
		shard.material_override = mat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(shard)
		shard.global_position = pos
		if dir.length_squared() > 0.001:
			shard.look_at(pos + dir, Vector3.UP)
		var travel := dir * randf_range(2.2, 4.6)
		var tw := shard.create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "global_position", pos + travel, 0.22)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.28)
		tw.chain().tween_callback(shard.queue_free)
