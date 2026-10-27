class_name Grenade
extends Node3D
## Server-simulated arc; only the server grenade explodes and deals damage.
## Clients run the same arc locally from the spawn velocity (the thrower starts it the moment
## they press G) and only blend toward the server's occasional pose corrections.
## Splash ignores teammates. The thrower can still hurt themselves.

const FUSE := 1.2
const THROW_SPEED := 18.0
const RADIUS := 5.5
const MAX_DAMAGE := 165.0
const BOUNCE := 0.42
const MASK := 1 | 2 | 4 # world, pawns, RC-XD (layer 4)
const BOOM_SFX := preload("res://assets/sounds/grenade_boom.wav")
const RC_BOOM_SFX := preload("res://assets/sounds/rcxd_boom.wav")

var thrower_id := 0
var thrower_team := 0
var velocity := Vector3.ZERO
var _fuse := FUSE
var _net_id := 0
var _sync_t := 0.0
## Client copy: simulates the same flight, never explodes; Game frees it on the server's boom.
var visual := false
var _net_pos := Vector3.ZERO
var _has_net := false
var _life := FUSE + 1.0 # a predicted throw the server refused frees itself after this

const POSE_SYNC := 0.1 # server corrections per grenade (the client simulates in between)
const SNAP_M := 2.5 # farther off than this: jump to the server pose
const CORRECT := 10.0 # 1/s blend toward the server pose


static func initial_velocity(dir: Vector3) -> Vector3:
	return dir.normalized() * THROW_SPEED + Vector3.UP * 4.0


## Client-side copy that flies on its own. `origin`/`vel` come from the thrower (prediction) or the spawn RPC.
static func spawn_visual(scene: Node, origin: Vector3, vel: Vector3) -> Grenade:
	var g := Grenade.new()
	g.visual = true
	g.velocity = vel
	scene.add_child(g)
	g.global_position = origin
	return g


func apply_net_pose(pos: Vector3) -> void:
	_net_pos = pos
	_has_net = true
	if global_position.distance_to(pos) > SNAP_M:
		global_position = pos


static func launch(thrower: Player, origin: Vector3, dir: Vector3, client_seq := 0) -> void:
	var g := Grenade.new()
	g.thrower_id = thrower.peer_id
	g.thrower_team = thrower.team_id
	g.velocity = Grenade.initial_velocity(dir)
	g._net_id = Game.next_grenade_id()
	var root := thrower.get_tree().current_scene
	root.add_child(g)
	g.global_position = origin
	if Game.is_networked():
		Game.sync_grenade_spawn.rpc(g._net_id, origin, g.velocity, thrower.peer_id, client_seq)


func _ready() -> void:
	add_to_group("grenade") # Game.reset_session frees leftovers on leave
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
	if visual:
		_tick_visual(delta)
		return
	if Game.is_networked() and not multiplayer.is_server():
		return
	_fuse -= delta
	_fly(delta)
	if Game.is_networked():
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = POSE_SYNC
			Game.sync_grenade_pose.rpc(_net_id, global_position)
	if _fuse <= 0.0:
		_explode()


func _tick_visual(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_fly(delta)
	if _has_net:
		# The server pose is from ~half a ping ago; a soft pull keeps bounces in step without hops.
		global_position = global_position.lerp(_net_pos, clampf(CORRECT * delta, 0.0, 1.0) * 0.5)


func _fly(delta: float) -> void:
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
		if visual and _has_net:
			_net_pos += motion # the correction target moves with the arc too


## Linear splash to 0 at RADIUS. 165 at the body is a kill; allow_headshot stays off.
func _explode() -> void:
	var pos := global_position
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead:
			continue
		if p != _thrower() and p.team_id == thrower_team and not Game.is_ffa():
			continue
		var dist := pos.distance_to(p.global_position + Vector3(0.0, 1.0, 0.0))
		if dist > RADIUS or not _blast_reaches(pos, p):
			continue
		var dmg := MAX_DAMAGE * (1.0 - dist / RADIUS)
		p.apply_hit(p.global_position + Vector3(0, 1, 0), Vector3.UP, dmg, false, thrower_id, &"grenade", 1.0, pos)
	Knockback.blast(pos, RADIUS, Knockback.GRENADE_POWER, thrower_id, thrower_team)
	# The listen-server host needs the boom too (the RPC skips the server). Headless has nobody to show it to.
	if not Game.is_dedicated:
		Grenade.play_boom(pos)
	if Game.is_networked():
		Game.sync_grenade_boom.rpc(pos, _net_id)
	queue_free()


## Walls block splash. Feet, chest, or head in the open is enough; other bodies do not shield.
func _blast_reaches(pos: Vector3, p: Player) -> bool:
	var space := get_world_3d().direct_space_state
	for h in [1.0, 1.6, 0.3]:
		var query := PhysicsRayQueryParameters3D.create(pos, p.global_position + Vector3(0.0, h, 0.0))
		query.collision_mask = 1
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _thrower() -> Player:
	return Game.player_for_peer(thrower_id)


## Local-only FX: flash, light, boom, and outward tracer shards.
## `heavy` is the RC-XD blast: its own clip, louder, and it carries farther than a frag.
static func play_boom(pos: Vector3, heavy := false) -> void:
	Game.killcam.note_boom(pos, heavy)
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
	sfx.stream = RC_BOOM_SFX if heavy else BOOM_SFX
	sfx.bus = "SFX"
	sfx.volume_db = 4.0 if heavy else 0.0
	sfx.unit_size = 16.0 if heavy else 10.0
	sfx.max_distance = 110.0 if heavy else 90.0 # a boom carries over the whole arena, muffled by the distance filter
	sfx.attenuation_filter_cutoff_hz = 3000.0
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
	tree.create_timer(2.3).timeout.connect(sfx.queue_free)


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
