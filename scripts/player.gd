class_name Player
extends CharacterBody3D
## Human or bot pawn. Same scene, same guns, same movement.
## Bots: `is_bot`, negative `peer_id`, server authority. Humans: authority = peer_id.

signal health_changed(hp: float, max_hp: float)
signal died
signal respawned

const WALK_SPEED := 7.6
const SPRINT_SPEED := 11.4
const CROUCH_SPEED := 3.5
const GROUND_ACCEL := 14.0
const GROUND_FRICTION := 10.0
const AIR_ACCEL := 3.5
const JUMP_SPEED := 7.6
const MOUSE_SENS := 0.00135
const MAX_PITCH := 1.5359
const STOP_SPEED := 1.5
const MAX_HP := 100.0
const RESPAWN_TIME := 2.0
const STAND_CAPSULE := 1.8
const CROUCH_CAPSULE := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.88
const CROUCH_BLEND := 12.0
const SPRINT_FOV := 6.0
const SPAWN_PROTECT := 1.8
const SLIDE_MIN := 0.35
const SLIDE_FRICTION := 2.4

@onready var head: Node3D = $Head
@onready var camera: CameraFeel = $Head/Camera3D
@onready var weapon: Weapon = $Head/Camera3D/WeaponRoot
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var hurt_sfx: AudioStreamPlayer = $HurtSfx
@onready var step_sfx: AudioStreamPlayer3D = $StepSfx
@onready var land_sfx: AudioStreamPlayer3D = $LandSfx
@onready var slide_sfx: AudioStreamPlayer3D = $SlideSfx
@onready var col_shape: CollisionShape3D = $CollisionShape3D
@onready var nametag: Label3D = $Nametag

const TEAM_COLORS := [Color(0.25, 0.55, 0.95), Color(0.92, 0.38, 0.22)]
const Brain := preload("res://scripts/bot_brain.gd")

const GRENADE_MAX := 2

var hp := MAX_HP
var grenades := GRENADE_MAX
@export var peer_id := 0
@export var is_dead := false
@export var is_bot := false
@export var team_id := 0
@export var loadout_index := 0
var is_sprinting := false
@export var crouch := 0.0
@export var display_name := "Player"
var _yaw := 0.0
var _pitch := 0.0
var _spawn_xform := Transform3D.IDENTITY
var _capsule: CapsuleShape3D
var _spawn_protect := 0.0
var _bot_brain
var _body_mat: StandardMaterial3D
var _radar_left := 0.0
var _radar_mark: MeshInstance3D
var _sliding := false
var _slide_t := 0.0
var _slide_dir := Vector3.FORWARD
var _step_t := 0.0
var _feet_last := Vector3.ZERO
var _was_air := false


## Bots are never "local" (no camera/input), even in offline 5v5.
func is_local() -> bool:
	if is_bot:
		return false
	if Game.is_offline:
		return true
	var id := _owner_peer()
	return id != 0 and id == multiplayer.get_unique_id()


func _owner_peer() -> int:
	if peer_id != 0:
		return peer_id
	if str(name).is_valid_int():
		return int(str(name))
	return 0


## Must run before MultiplayerSynchronizer starts. Bots always belong to peer 1.
func _enter_tree() -> void:
	_restore_bot_identity()
	if Game.is_offline:
		return
	if peer_id == 0 and str(name).is_valid_int():
		peer_id = int(str(name))
	if is_bot or peer_id < 0:
		set_multiplayer_authority(1, true)
	elif peer_id > 0:
		set_multiplayer_authority(peer_id, true)


## Late-join copies may only have the node name `bot7`; recover peer_id from that.
func _restore_bot_identity() -> void:
	var n := str(name)
	if n.begins_with("bot") and n.substr(3).is_valid_int():
		is_bot = true
		if peer_id >= 0:
			peer_id = -int(n.substr(3))


func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 0.2
	collision_layer = 2
	collision_mask = 1
	_spawn_xform = global_transform
	_capsule = col_shape.shape.duplicate() as CapsuleShape3D
	col_shape.shape = _capsule
	if peer_id == 0:
		peer_id = _owner_peer()
	_dup_body_mat()
	_apply_team_visual()
	# Bots/offline skip MultiplayerSynchronizer; bot poses are Game.sync_bot_poses.
	if has_node("Sync") and (Game.is_offline or is_bot or peer_id < 0):
		$Sync.public_visibility = false
	if Game.is_offline:
		pass
	elif is_bot or peer_id < 0:
		set_multiplayer_authority(1, true)
	elif peer_id > 0:
		set_multiplayer_authority(peer_id, true)
	_spawn_protect = SPAWN_PROTECT
	_feet_last = global_position
	if is_bot and (Game.is_offline or multiplayer.is_server()):
		_bot_brain = Brain.new()
		_bot_brain.setup(self, get_node_or_null("NavigationAgent3D") as NavigationAgent3D)
	if is_bot:
		call_deferred("_apply_bot_loadout")
	_radar_mark = _make_radar_mark()
	add_child(_radar_mark)
	call_deferred("_configure_control")


func _make_radar_mark() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.emission_enabled = true
	mat.emission = Color(1, 0.35, 0.2)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	mesh.position = Vector3(0, 2.35, 0)
	mesh.visible = false
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## Only the client that earned the streak calls this. Other machines keep it hidden.
func show_radar_marker(seconds: float) -> void:
	if _radar_mark == null:
		return
	var mat := _radar_mark.material_override as StandardMaterial3D
	if mat:
		var col: Color = TEAM_COLORS[clampi(team_id, 0, 1)]
		mat.albedo_color = col
		mat.emission = col
	_radar_left = seconds
	_radar_mark.visible = true


func _process(delta: float) -> void:
	if _radar_mark == null:
		return
	if is_dead:
		_radar_left = 0.0
		_radar_mark.visible = false
		return
	if _radar_left <= 0.0:
		return
	_radar_left = maxf(_radar_left - delta, 0.0)
	_radar_mark.visible = _radar_left > 0.0


func _apply_bot_loadout() -> void:
	if weapon:
		weapon.equip_loadout(loadout_index)


## Local: hide body, capture mouse. Remote/bot: show mesh, nametag, world gun.
func _configure_control() -> void:
	_apply_team_visual()
	if is_local():
		body_mesh.visible = false
		weapon.visible = true
		nametag.visible = false
		if Game.player_name != "":
			set_display_name(Game.player_name)
		make_active_camera()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.local_player_ready.emit(self)
		health_changed.emit(hp, MAX_HP)
		_notify_grenades()
		if Game.is_networked() and not multiplayer.is_server():
			Game.submit_display_name.rpc_id(1, Game.player_name)
	else:
		body_mesh.visible = not is_dead
		camera.current = false
		weapon.visible = true
		nametag.visible = true
		set_display_name(display_name)


func make_active_camera() -> void:
	var menu_cam := get_tree().get_first_node_in_group("menu_camera") as Camera3D
	if menu_cam:
		menu_cam.current = false
	camera.current = true


func _input(event: InputEvent) -> void:
	if not is_local():
		return
	if Game.chat_open or Game.pause_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS
		if weapon and weapon.is_ads():
			sens *= 0.45 # match Scout-style zoom so flicks stay controllable
		_yaw -= event.relative.x * sens
		_pitch -= event.relative.y * sens
		_pitch = clampf(_pitch, -MAX_PITCH, MAX_PITCH)
		rotation.y = _yaw
		head.rotation.x = _pitch
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	if Game.chat_open or Game.pause_open:
		return
	if event.is_action_pressed("grenade") and not is_dead and not Game.round_frozen:
		_try_throw_grenade()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func set_display_name(n: String) -> void:
	display_name = n
	if nametag:
		nametag.text = n
		nametag.modulate = TEAM_COLORS[team_id]


func _dup_body_mat() -> void:
	if body_mesh == null:
		return
	var src := body_mesh.get_active_material(0)
	if src is StandardMaterial3D:
		_body_mat = (src as StandardMaterial3D).duplicate()
	else:
		_body_mat = StandardMaterial3D.new()
	body_mesh.set_surface_override_material(0, _body_mat)


func _apply_team_visual() -> void:
	var col: Color = TEAM_COLORS[clampi(team_id, 0, TEAM_COLORS.size() - 1)]
	if _body_mat:
		_body_mat.albedo_color = col
		_body_mat.emission_enabled = true
		_body_mat.emission = col * 0.45
		_body_mat.emission_energy_multiplier = 0.7
	if nametag:
		nametag.modulate = col


## Damage is applied on the server (or offline). Clients get HP via broadcast_hurt.
func apply_hit(point: Vector3, _normal: Vector3, base_damage: float, allow_headshot: bool = true, killer_peer_id: int = 0, weapon_id: StringName = &"rifle") -> Dictionary:
	if is_dead or _spawn_protect > 0.0:
		return {"killed": false, "headshot": false, "damage": 0}
	if Game.is_networked() and not multiplayer.is_server():
		return {"killed": false, "headshot": false, "damage": 0}
	var headshot := allow_headshot and point.y >= global_position.y + lerpf(1.45, 0.75, crouch)
	var dmg := roundi(base_damage * (1.6 if headshot else 1.0))
	var new_hp := maxf(Game.hp_of(self) - float(dmg), 0.0)
	Game.set_hp(self, new_hp)
	var killed := new_hp <= 0.0
	if killed:
		Game.register_kill(killer_peer_id, peer_id, weapon_id)
	if Game.is_networked():
		Game.broadcast_hurt.rpc(peer_id, new_hp, killed)
	else:
		apply_hurt_state(new_hp, killed)
	return {"killed": killed, "headshot": headshot, "damage": dmg}


func apply_hurt_state(new_hp: float, killed: bool) -> void:
	hp = new_hp
	if is_local():
		camera.add_kick(0.85, randf_range(-0.35, 0.35), 2.2)
		if hurt_sfx.stream:
			hurt_sfx.pitch_scale = randf_range(0.92, 1.08)
			hurt_sfx.play()
		health_changed.emit(hp, MAX_HP)
	if killed:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	collision_layer = 0
	if is_local():
		weapon.visible = false
		died.emit()
	else:
		body_mesh.visible = false
		weapon.visible = false
	if Game.is_offline or multiplayer.is_server():
		get_tree().create_timer(RESPAWN_TIME).timeout.connect(_server_respawn)


func _server_respawn() -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	Game.set_hp(self, MAX_HP)
	if Game.is_networked():
		Game.broadcast_respawn.rpc(peer_id)
	else:
		apply_respawn_state()


func apply_respawn_state() -> void:
	hp = MAX_HP
	is_dead = false
	_spawn_protect = SPAWN_PROTECT
	collision_layer = 2
	velocity = Vector3.ZERO
	crouch = 0.0
	is_sprinting = false
	global_transform = _spawn_xform
	_yaw = rotation.y
	_pitch = 0.0
	head.rotation.x = 0.0
	weapon.visible = true
	grenades = GRENADE_MAX
	_notify_grenades()
	if weapon:
		weapon.refill()
	_apply_stance()
	_apply_team_visual()
	if is_local():
		health_changed.emit(hp, MAX_HP)
		respawned.emit()
	else:
		body_mesh.visible = true


## G. Offline/host throws here; a client only sends origin and look direction.
func _try_throw_grenade() -> void:
	if grenades <= 0 or camera == null:
		return
	var origin := camera.global_position + (-camera.global_basis.z) * 0.6
	var dir := -camera.global_basis.z
	if Game.is_networked() and not multiplayer.is_server():
		Game.request_grenade.rpc_id(1, origin, dir)
	else:
		Game.throw_grenade(self, origin, dir)


func _notify_grenades() -> void:
	if not is_local():
		return
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_grenades(grenades)


## 1.0 is standing still. Walk, sprint, then slide stack on top of the gun's own spread.
func spread_multiplier() -> float:
	# Still is the accurate state. Slide is wider than sprint, which is wider than walking.
	if is_sliding():
		return 8.0
	if is_sprinting:
		return 6.0
	var move := minf(Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 1.0)
	return 1.0 + move * 1.15


## Server simulates bots. Remote humans/bots on a client only apply visuals + footsteps.
func _physics_process(delta: float) -> void:
	_spawn_protect = maxf(_spawn_protect - delta, 0.0)
	if is_bot:
		if Game.is_networked() and not multiplayer.is_server():
			_apply_remote_visual()
			_tick_feet(delta)
			return
		if _bot_brain:
			_bot_brain.physics_tick(delta)
		_tick_feet(delta)
		return
	if not is_local():
		_apply_remote_visual()
		_tick_feet(delta)
		return
	var chatting := Game.chat_open or Game.round_frozen
	var on_floor := is_on_floor()
	_try_start_slide(on_floor, chatting)
	_update_stance(delta, on_floor)

	if not on_floor:
		velocity.y += float(get_gravity().y) * delta
		_sliding = false
	elif (not is_dead) and (not chatting) and Input.is_action_just_pressed("jump"):
		_sliding = false
		if crouch > 0.2:
			if not _ceiling_blocked():
				crouch = 0.0
				_apply_stance()
				velocity.y = JUMP_SPEED
		else:
			velocity.y = JUMP_SPEED

	var input_vec := Vector2.ZERO
	if not is_dead and not chatting:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	elif input_vec.length_squared() > 0.0001:
		wish = wish.normalized() * minf(input_vec.length(), 1.0)

	var wish_speed := WALK_SPEED
	is_sprinting = false
	if _sliding:
		wish = _slide_dir
		wish_speed = SPRINT_SPEED
		is_sprinting = false
	elif on_floor and (not is_dead) and (not chatting) and crouch < 0.2 and Input.is_action_pressed("sprint") and wish.length_squared() > 0.04:
		wish_speed = SPRINT_SPEED
		is_sprinting = true
	elif crouch > 0.5:
		wish_speed = CROUCH_SPEED

	camera.extra_fov = 0.0 if weapon.is_ads() else (SPRINT_FOV if is_sprinting else 0.0)

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor and _sliding:
		horiz = _friction_amount(horiz, delta, SLIDE_FRICTION)
	elif on_floor:
		horiz = _friction(horiz, delta)
		horiz = _accelerate(horiz, wish, wish_speed, GROUND_ACCEL, delta)
	else:
		horiz = _accelerate(horiz, wish, WALK_SPEED, AIR_ACCEL, delta)

	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	_finish_slide()
	_tick_feet(delta)

	weapon.speed_factor = Vector2(velocity.x, velocity.z).length() / WALK_SPEED


## Uses velocity when we simulate, otherwise position delta (puppets have velocity zeroed).
func _tick_feet(delta: float) -> void:
	if is_dead:
		_was_air = false
		_feet_last = global_position
		return
	var dpos := global_position - _feet_last
	var horiz := Vector2(velocity.x, velocity.z).length()
	if horiz < 0.35:
		horiz = Vector2(dpos.x, dpos.z).length() / maxf(delta, 0.0001)
	var grounded := is_on_floor() or absf(dpos.y) < 0.05
	if _was_air and grounded and land_sfx:
		land_sfx.pitch_scale = randf_range(0.92, 1.06)
		land_sfx.volume_db = -14.0 if is_local() else -8.0
		land_sfx.play()
	_was_air = not grounded
	_feet_last = global_position
	if _sliding:
		_step_t = 0.2
		return
	if not grounded or horiz < 1.15:
		_step_t = 0.12
		return
	var interval := 0.40
	if crouch > 0.45:
		interval = 0.52
	elif horiz > WALK_SPEED * 1.15:
		interval = 0.28
	_step_t -= delta
	if _step_t > 0.0:
		return
	_step_t = interval
	if step_sfx == null:
		return
	step_sfx.pitch_scale = randf_range(0.90, 1.10)
	var quiet := -16.0 if is_local() else -9.0
	if crouch > 0.45:
		quiet -= 6.0
	step_sfx.volume_db = quiet
	step_sfx.play()


## Client-side bot transform from Game.sync_bot_poses (Synchronizer is off for bots).
func apply_network_pose(pos: Vector3, yaw: float, pitch: float) -> void:
	global_position = pos
	rotation.y = yaw
	_yaw = yaw
	_pitch = pitch
	if head:
		head.rotation.x = pitch
	velocity = Vector3.ZERO
	if body_mesh:
		body_mesh.visible = not is_dead
	if nametag:
		nametag.visible = true
		nametag.text = display_name


func _apply_remote_visual() -> void:
	_apply_stance()
	_apply_team_visual()
	body_mesh.visible = not is_dead
	weapon.visible = not is_dead
	collision_layer = 0 if is_dead else 2
	if nametag:
		nametag.text = display_name


func is_sliding() -> bool:
	return _sliding


## Sprint, or already faster than a walk, plus crouch. Plain crouch stays the slow stance.
func _try_start_slide(on_floor: bool, locked: bool) -> void:
	if _sliding or locked or is_dead or not on_floor:
		return
	if not Input.is_action_just_pressed("crouch"):
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_sprinting and speed < WALK_SPEED * 1.05:
		return
	_sliding = true
	_slide_t = 0.0
	_slide_dir = Vector3(velocity.x, 0.0, velocity.z)
	if _slide_dir.length_squared() < 0.04:
		_slide_dir = -transform.basis.z
	_slide_dir = _slide_dir.normalized()
	crouch = 1.0
	if slide_sfx:
		slide_sfx.play()


## Minimum time so a tap still slides. After that: release, slow down, or a wall ends it.
func _finish_slide() -> void:
	if not _sliding:
		return
	_slide_t += get_physics_process_delta_time()
	var speed := Vector2(velocity.x, velocity.z).length()
	var release := not Input.is_action_pressed("crouch")
	var slow := speed < WALK_SPEED * 0.95
	var wall := false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.45:
			wall = true
			break
	if _slide_t >= SLIDE_MIN and (release or slow or wall or not is_on_floor()):
		_sliding = false


func _update_stance(delta: float, _on_floor: bool) -> void:
	var want := _sliding or ((not is_dead) and (not Game.chat_open) and Input.is_action_pressed("crouch"))
	if (not want) and crouch > 0.05 and _ceiling_blocked():
		want = true
	var target := 1.0 if want else 0.0
	crouch = move_toward(crouch, target, CROUCH_BLEND * delta)
	_apply_stance()


func _apply_stance() -> void:
	if _capsule == null:
		return
	var h := lerpf(STAND_CAPSULE, CROUCH_CAPSULE, crouch)
	_capsule.height = h
	col_shape.position.y = h * 0.5
	head.position.y = lerpf(STAND_EYE, CROUCH_EYE, crouch)
	if body_mesh:
		body_mesh.position.y = h * 0.5
		body_mesh.scale.y = h / STAND_CAPSULE


func _ceiling_blocked() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, CROUCH_CAPSULE + 0.02, 0.0)
	var to := global_position + Vector3(0.0, STAND_CAPSULE + 0.02, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return space.intersect_ray(query).has("collider")


## Quake-style stop: no Godot default air float.
func _friction(vel: Vector3, delta: float) -> Vector3:
	return _friction_amount(vel, delta, GROUND_FRICTION)


func _friction_amount(vel: Vector3, delta: float, friction: float) -> Vector3:
	var speed := vel.length()
	if speed < 0.01:
		return Vector3.ZERO
	var control := STOP_SPEED if speed < STOP_SPEED else speed
	var drop := control * friction * delta
	var new_speed := maxf(speed - drop, 0.0)
	return vel * (new_speed / speed)


func _accelerate(vel: Vector3, wish: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	if wish.length_squared() < 0.0001:
		return vel
	var wish_dir := wish.normalized()
	var current := vel.dot(wish_dir)
	var add := wish_speed - current
	if add <= 0.0:
		return vel
	var acc := minf(accel * wish_speed * delta, add)
	return vel + wish_dir * acc
