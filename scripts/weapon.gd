class_name Weapon
extends Node3D

const HURT_MASK := 1 | 2 | 4

@export var def: WeaponDef

@onready var camera: CameraFeel = get_parent() as CameraFeel
@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: MeshInstance3D = $Muzzle/Flash
@onready var muzzle_light: OmniLight3D = $Muzzle/FlashLight
@onready var fire_sfx: AudioStreamPlayer = $FireSfx
@onready var hit_sfx: AudioStreamPlayer = $HitSfx
@onready var head_sfx: AudioStreamPlayer = $HeadSfx
@onready var kill_sfx: AudioStreamPlayer = $KillSfx
@onready var empty_sfx: AudioStreamPlayer = $EmptySfx

var speed_factor := 0.0
var ammo: int = 30
var _cooldown := 0.0
var _reload_left := 0.0
var _flash_left := 0.0
var _kick_offset := Vector3.ZERO
var _bob_t := 0.0
var _rest_pos: Vector3
var _hud: Hud


func _ready() -> void:
	if def == null:
		def = load("res://data/weapons/rifle.tres") as WeaponDef
	ammo = def.mag_size
	_rest_pos = position
	muzzle_flash.visible = false
	muzzle_light.visible = false
	call_deferred("_hook_hit_fx")
	_refresh_hud()


func _hook_hit_fx() -> void:
	if _is_local() and not Game.hit_confirmed.is_connected(_on_confirmed_hit):
		Game.hit_confirmed.connect(_on_confirmed_hit)


func _process(delta: float) -> void:
	if not _is_local():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left <= 0.0:
		muzzle_flash.visible = false
		muzzle_light.visible = false

	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		var t := 1.0 - (_reload_left / def.reload_time)
		rotation.x = sin(t * PI) * 0.55
		if _reload_left <= 0.0:
			ammo = def.mag_size
			rotation.x = 0.0
			_refresh_hud()
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _owner_alive():
		if Input.is_action_just_pressed("reload") and ammo < def.mag_size:
			_start_reload()
		elif Input.is_action_pressed("fire"):
			_try_fire()

	_kick_offset = _kick_offset.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * delta))
	_bob_t += delta * (8.0 + speed_factor * 6.0)
	var bob := Vector3.ZERO
	if speed_factor > 0.08:
		bob.x = sin(_bob_t) * 0.012 * speed_factor
		bob.y = absf(sin(_bob_t * 2.0)) * 0.01 * speed_factor
	position = _rest_pos + _kick_offset + bob


func _try_fire() -> void:
	if _cooldown > 0.0 or _reload_left > 0.0:
		return
	if ammo <= 0:
		_start_reload()
		if empty_sfx.stream:
			empty_sfx.play()
		return
	_fire()


func _fire() -> void:
	ammo -= 1
	_cooldown = 1.0 / def.fire_rate
	_kick_offset += Vector3(0.0, 0.0, 0.055)
	_kick_offset.y += randf_range(-0.008, 0.004)
	_flash_left = 0.045
	muzzle_flash.visible = true
	muzzle_light.visible = true
	muzzle_light.light_energy = 4.5
	if fire_sfx.stream:
		fire_sfx.pitch_scale = randf_range(0.96, 1.05)
		fire_sfx.play()

	var yaw_kick := randf_range(-def.kick_yaw_deg, def.kick_yaw_deg)
	camera.add_kick(def.kick_pitch_deg, yaw_kick, def.kick_fov)
	var hud := _hud_node()
	if hud:
		hud.punch_crosshair(_crosshair_punch())
	_refresh_hud()

	var origin := camera.global_position
	var dir := _spread(-camera.global_transform.basis.z, _current_spread())
	var to := origin + dir * def.range_m
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = HURT_MASK
	var player_body := owner as CollisionObject3D
	if player_body:
		query.exclude = [player_body.get_rid()]
	var hit := space.intersect_ray(query)
	var end: Vector3 = to
	if hit:
		end = hit.position
		_spawn_spark(hit.position, hit.normal)
	_spawn_tracer(muzzle.global_position, end)

	var shooter := owner as Player
	if Game.is_networked() and not multiplayer.is_server():
		Game.request_shot.rpc_id(1, origin, dir, def.range_m, def.damage, def.headshot_multiplier)
	elif hit:
		_apply_hit(hit, shooter)

	if ammo <= 0:
		_start_reload()


func _apply_hit(hit: Dictionary, shooter: Player) -> void:
	if shooter == null:
		return
	var result := Game.apply_shot_locally(shooter, hit, def.damage, def.headshot_multiplier)
	if result.is_empty():
		return
	Game.hit_confirmed.emit(result.killed, result.headshot)
	_play_hit_fx(result.killed, result.headshot)


func _on_confirmed_hit(killed: bool, headshot: bool) -> void:
	if Game.is_offline or multiplayer.is_server():
		return
	_play_hit_fx(killed, headshot)


func _play_hit_fx(killed: bool, headshot: bool) -> void:
	if killed:
		if kill_sfx.stream:
			kill_sfx.play()
		Game.hitstop()
	elif headshot:
		if head_sfx.stream:
			head_sfx.play()
	elif hit_sfx.stream:
		hit_sfx.play()


func _current_spread() -> float:
	var spread := def.spread_deg
	var p := owner as Player
	if p:
		spread *= p.spread_multiplier()
	return spread


func _crosshair_punch() -> float:
	var p := owner as Player
	if p and p.is_sprinting:
		return 1.6
	return 1.0


func refill() -> void:
	ammo = def.mag_size
	_reload_left = 0.0
	rotation.x = 0.0
	_refresh_hud()


func _is_local() -> bool:
	var p := owner as Player
	return p == null or p.is_local()


func _owner_alive() -> bool:
	var p := owner as Player
	return p == null or not p.is_dead


func _start_reload() -> void:
	if _reload_left > 0.0 or ammo == def.mag_size:
		return
	_reload_left = def.reload_time
	_refresh_hud()


func _hud_node() -> Hud:
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud") as Hud
	return _hud


func _refresh_hud() -> void:
	if not _is_local():
		return
	var hud := _hud_node()
	if hud:
		hud.set_ammo(ammo, def.mag_size)
		hud.set_weapon_name(def.display_name)
		hud.set_reloading(_reload_left > 0.0)


func _spread(forward: Vector3, deg: float) -> Vector3:
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


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(def.tracer_width, def.tracer_width, length)
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


func _spawn_spark(pos: Vector3, normal: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.25)
	spark.mesh = sphere
	spark.material_override = mat
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(spark)
	spark.global_position = pos + normal * 0.04
	get_tree().create_timer(0.04).timeout.connect(spark.queue_free)
