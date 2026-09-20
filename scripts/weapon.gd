class_name Weapon
extends Node3D

const HURT_MASK := 1 | 2 | 4
const LOADOUT: Array[WeaponDef] = [
	preload("res://data/weapons/rifle.tres"),
	preload("res://data/weapons/pistol.tres"),
	preload("res://data/weapons/shotgun.tres"),
]

@export var def: WeaponDef

@onready var camera: CameraFeel = get_parent() as CameraFeel
@onready var gun_body: MeshInstance3D = $GunBody
@onready var barrel: MeshInstance3D = $Barrel
@onready var mag: MeshInstance3D = $Mag
@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: MeshInstance3D = $Muzzle/Flash
@onready var muzzle_light: OmniLight3D = $Muzzle/FlashLight
@onready var fire_sfx: AudioStreamPlayer3D = $FireSfx
@onready var hit_sfx: AudioStreamPlayer = $HitSfx
@onready var head_sfx: AudioStreamPlayer = $HeadSfx
@onready var kill_sfx: AudioStreamPlayer = $KillSfx
@onready var empty_sfx: AudioStreamPlayer = $EmptySfx
@onready var reload_sfx: AudioStreamPlayer3D = $ReloadSfx

var speed_factor := 0.0
var ammo: int = 30
var _cooldown := 0.0
var _reload_left := 0.0
var _flash_left := 0.0
var _kick_offset := Vector3.ZERO
var _bob_t := 0.0
var _rest_pos: Vector3
var _hud: Hud
var _weapon_state: Dictionary = {}
var _active_index := 0


func _ready() -> void:
	if def == null:
		def = LOADOUT[0]
	_rest_pos = position
	muzzle_flash.visible = false
	muzzle_light.visible = false
	_active_index = _index_for_def(def)
	_equip(_active_index, false)
	call_deferred("_hook_hit_fx")


func _hook_hit_fx() -> void:
	if _is_local() and not Game.hit_confirmed.is_connected(_on_confirmed_hit):
		Game.hit_confirmed.connect(_on_confirmed_hit)


func _process(delta: float) -> void:
	var owner_player := owner as Player
	var bot_auth := owner_player != null and owner_player.is_bot and (Game.is_offline or multiplayer.is_server())
	if not _is_local() and not bot_auth:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left <= 0.0:
		muzzle_flash.visible = false
		muzzle_light.visible = false
	if bot_auth:
		if _reload_left > 0.0:
			_reload_left = maxf(_reload_left - delta, 0.0)
			if _reload_left <= 0.0:
				ammo = def.mag_size
				_save_weapon_state()
		return

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _owner_alive():
		if Input.is_action_just_pressed("switch_weapon"):
			_cycle_weapon()
		elif Input.is_action_just_pressed("weapon_1"):
			_equip(0)
		elif Input.is_action_just_pressed("weapon_2"):
			_equip(1)
		elif Input.is_action_just_pressed("weapon_3"):
			_equip(2)
		elif _reload_left > 0.0:
			pass
		elif Input.is_action_just_pressed("reload") and ammo < def.mag_size:
			_start_reload()
		elif _wants_fire():
			_try_fire()
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		var t := 1.0 - (_reload_left / def.reload_time)
		rotation.x = sin(t * PI) * 0.55
		if _reload_left <= 0.0:
			ammo = def.mag_size
			_save_weapon_state()
			rotation.x = 0.0
			_refresh_hud()

	_kick_offset = _kick_offset.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * delta))
	_bob_t += delta * (8.0 + speed_factor * 6.0)
	var bob := Vector3.ZERO
	if speed_factor > 0.08:
		bob.x = sin(_bob_t) * 0.012 * speed_factor
		bob.y = absf(sin(_bob_t * 2.0)) * 0.01 * speed_factor
	position = _rest_pos + _kick_offset + bob


func _wants_fire() -> bool:
	if def.automatic:
		return Input.is_action_pressed("fire")
	return Input.is_action_just_pressed("fire")


func _cycle_weapon() -> void:
	if not _owner_alive():
		return
	_equip((_active_index + 1) % LOADOUT.size())


func equip_loadout(index: int) -> void:
	_equip(clampi(index, 0, LOADOUT.size() - 1), false)


func _equip(index: int, save_current: bool = true) -> void:
	index = clampi(index, 0, LOADOUT.size() - 1)
	if save_current and def != null and index == _active_index:
		return
	if save_current and def != null:
		_cancel_reload()
		_save_weapon_state()
	_active_index = index
	def = LOADOUT[index]
	var state := _load_weapon_state(def.id)
	ammo = int(state.ammo)
	_reload_left = 0.0
	rotation.x = 0.0
	if def.fire_sound:
		fire_sfx.stream = def.fire_sound
	_apply_view_for_def()
	_refresh_hud()


func _cancel_reload() -> void:
	_reload_left = 0.0
	rotation.x = 0.0
	if reload_sfx and reload_sfx.playing:
		reload_sfx.stop()
	var hud := _hud_node()
	if hud:
		hud.set_reloading(false)


func _save_weapon_state() -> void:
	if def == null:
		return
	_weapon_state[def.id] = {"ammo": ammo, "reload_left": _reload_left}


func _load_weapon_state(id: StringName) -> Dictionary:
	if not _weapon_state.has(id):
		var weapon_def := _def_for_id(id)
		_weapon_state[id] = {
			"ammo": weapon_def.mag_size if weapon_def else 0,
			"reload_left": 0.0,
		}
	return _weapon_state[id]


func _def_for_id(id: StringName) -> WeaponDef:
	for weapon_def in LOADOUT:
		if weapon_def.id == id:
			return weapon_def
	return null


func _index_for_def(weapon_def: WeaponDef) -> int:
	for i in LOADOUT.size():
		if LOADOUT[i].id == weapon_def.id:
			return i
	return 0


func _apply_view_for_def() -> void:
	mag.visible = true
	match def.id:
		&"pistol":
			position = Vector3(0.22, -0.16, -0.34)
			gun_body.scale = Vector3(0.72, 0.72, 0.72)
			barrel.scale = Vector3(0.85, 0.85, 0.55)
			barrel.position = Vector3(0.0, 0.02, -0.18)
			mag.scale = Vector3(0.7, 0.65, 0.7)
			mag.position = Vector3(0.0, -0.08, 0.01)
			muzzle.position = Vector3(0.0, 0.02, -0.28)
		&"shotgun":
			position = Vector3(0.26, -0.17, -0.38)
			gun_body.scale = Vector3(1.1, 0.95, 1.05)
			barrel.scale = Vector3(1.35, 1.2, 0.42)
			barrel.position = Vector3(0.0, 0.03, -0.22)
			mag.visible = false
			muzzle.position = Vector3(0.0, 0.03, -0.36)
		_:
			position = _rest_pos
			gun_body.scale = Vector3.ONE
			barrel.scale = Vector3.ONE
			barrel.position = Vector3(0.0, 0.02, -0.28)
			mag.scale = Vector3.ONE
			mag.position = Vector3(0.0, -0.1, 0.02)
			muzzle.position = Vector3(0.0, 0.02, -0.49)


func _try_fire() -> void:
	if _cooldown > 0.0 or _reload_left > 0.0:
		return
	if ammo <= 0:
		_start_reload()
		if empty_sfx.stream:
			empty_sfx.play()
		return
	_fire()


func play_fire_sfx() -> void:
	if fire_sfx == null or fire_sfx.stream == null:
		return
	fire_sfx.pitch_scale = randf_range(0.96, 1.05)
	fire_sfx.play()


func bot_try_fire() -> bool:
	if _cooldown > 0.0 or _reload_left > 0.0:
		return false
	if ammo <= 0:
		_start_reload()
		return false
	_fire()
	return true


func _fire() -> void:
	ammo -= 1
	_save_weapon_state()
	_cooldown = 1.0 / def.fire_rate
	var kick_z := 0.055 if def.id != &"shotgun" else 0.09
	_kick_offset += Vector3(0.0, 0.0, kick_z)
	_kick_offset.y += randf_range(-0.008, 0.004)
	_flash_left = 0.06 if def.id == &"shotgun" else 0.045
	muzzle_flash.visible = true
	muzzle_light.visible = true
	muzzle_light.light_energy = 5.5 if def.id == &"shotgun" else 4.5
	play_fire_sfx()

	var shooter := owner as Player
	if shooter == null or not shooter.is_bot:
		var yaw_kick := randf_range(-def.kick_yaw_deg, def.kick_yaw_deg)
		camera.add_kick(def.kick_pitch_deg, yaw_kick, def.kick_fov)
		var hud := _hud_node()
		if hud:
			hud.punch_crosshair(_crosshair_punch())
		_refresh_hud()

	var origin := camera.global_position
	var look_dir := -camera.global_transform.basis.z
	var tracer_to := _simulate_pellets_fx(origin, look_dir)
	if Game.is_networked() and multiplayer.is_server() and shooter:
		Game.broadcast_shot_fx(muzzle.global_position, tracer_to, shooter.peer_id)

	var spread_mult := _spread_multiplier()
	if shooter and shooter.is_bot:
		if def.id == &"shotgun":
			spread_mult *= 1.2
		elif def.id == &"pistol":
			spread_mult *= 1.9
		else:
			spread_mult *= 2.4
	if Game.is_networked() and not multiplayer.is_server():
		Game.request_weapon_fire.rpc_id(1, origin, look_dir, def.id, muzzle.global_position)
	elif shooter:
		var best: Dictionary = Game.fire_weapon_locally(shooter, origin, look_dir, def, spread_mult)
		if best.get("hit", false) and not shooter.is_bot:
			Game.hit_confirmed.emit(best.killed, best.headshot)
			_play_hit_fx(best.killed, best.headshot)

	if ammo <= 0:
		_start_reload()


func _simulate_pellets_fx(origin: Vector3, look_dir: Vector3) -> Vector3:
	var spread := def.spread_deg * _spread_multiplier()
	var space := camera.get_world_3d().direct_space_state
	var player_body := owner as CollisionObject3D
	var tracer_end := origin + look_dir * def.range_m
	for i in def.pellet_count:
		var dir := _spread(look_dir, spread)
		var to := origin + dir * def.range_m
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.collision_mask = HURT_MASK
		if player_body:
			query.exclude = [player_body.get_rid()]
		var hit := space.intersect_ray(query)
		var end: Vector3 = to
		if hit:
			end = hit.position
			_spawn_spark(hit.position, hit.normal)
		_spawn_tracer(muzzle.global_position, end)
		if i == 0:
			tracer_end = end
	return tracer_end


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


func _spread_multiplier() -> float:
	var p := owner as Player
	if p == null or def.spread_deg <= 0.0:
		return 1.0
	return _current_spread() / def.spread_deg


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
	if def.id == &"shotgun":
		return 2.2
	return 1.0


func refill() -> void:
	for weapon_def in LOADOUT:
		_weapon_state[weapon_def.id] = {
			"ammo": weapon_def.mag_size,
			"reload_left": 0.0,
		}
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
	_save_weapon_state()
	_play_reload_sfx()
	_refresh_hud()


func _play_reload_sfx() -> void:
	if reload_sfx == null or reload_sfx.stream == null:
		return
	var src_len := reload_sfx.stream.get_length()
	if src_len > 0.05 and def.reload_time > 0.05:
		reload_sfx.pitch_scale = clampf(src_len / def.reload_time, 0.85, 1.75)
	else:
		reload_sfx.pitch_scale = 1.0
	reload_sfx.play()


func _hud_node() -> Hud:
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud") as Hud
	return _hud


func _refresh_hud() -> void:
	if not _is_local():
		return
	var hud := _hud_node()
	if hud:
		hud.set_weapon_index(_active_index)
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
	if def.id == &"shotgun":
		mat.albedo_color = Color(1.0, 0.65, 0.2)
		mat.emission = Color(1.0, 0.5, 0.1)
	else:
		mat.albedo_color = Color(1.0, 0.82, 0.28)
		mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_enabled = true
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
