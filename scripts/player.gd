class_name Player
extends CharacterBody3D

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

@onready var head: Node3D = $Head
@onready var camera: CameraFeel = $Head/Camera3D
@onready var weapon: Weapon = $Head/Camera3D/WeaponRoot
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var hurt_sfx: AudioStreamPlayer = $HurtSfx
@onready var col_shape: CollisionShape3D = $CollisionShape3D
@onready var nametag: Label3D = $Nametag

var hp := MAX_HP
@export var peer_id := 0
@export var is_dead := false
var is_sprinting := false
@export var crouch := 0.0
@export var display_name := "Player"
var _yaw := 0.0
var _pitch := 0.0
var _spawn_xform := Transform3D.IDENTITY
var _capsule: CapsuleShape3D
var _spawn_protect := 0.0


func is_local() -> bool:
	if Game.is_offline:
		return true
	var id := _owner_peer()
	return id != 0 and id == multiplayer.get_unique_id()


func _owner_peer() -> int:
	if peer_id > 0:
		return peer_id
	if str(name).is_valid_int():
		return int(str(name))
	return 0


func _enter_tree() -> void:
	if Game.is_offline:
		return
	if peer_id <= 0 and str(name).is_valid_int():
		peer_id = int(str(name))
	if peer_id > 0:
		set_multiplayer_authority(peer_id, true)


func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 0.2
	collision_layer = 2
	collision_mask = 1 | 4
	_spawn_xform = global_transform
	_capsule = col_shape.shape.duplicate() as CapsuleShape3D
	col_shape.shape = _capsule
	if peer_id <= 0:
		peer_id = _owner_peer()
	if Game.is_offline:
		if has_node("Sync"):
			$Sync.public_visibility = false
	elif peer_id > 0:
		set_multiplayer_authority(peer_id, true)
	_spawn_protect = SPAWN_PROTECT
	call_deferred("_configure_control")


func _configure_control() -> void:
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
		if Game.is_networked() and not multiplayer.is_server():
			Game.submit_display_name.rpc_id(1, Game.player_name)
	else:
		body_mesh.visible = not is_dead
		camera.current = false
		weapon.visible = false
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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch -= event.relative.y * MOUSE_SENS
		_pitch = clampf(_pitch, -MAX_PITCH, MAX_PITCH)
		rotation.y = _yaw
		head.rotation.x = _pitch
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	if event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func set_display_name(n: String) -> void:
	display_name = n
	if nametag:
		nametag.text = n


func apply_hit(point: Vector3, _normal: Vector3, base_damage: float, allow_headshot: bool = true) -> Dictionary:
	if is_dead or _spawn_protect > 0.0:
		return {"killed": false, "headshot": false, "damage": 0}
	if Game.is_networked() and not multiplayer.is_server():
		return {"killed": false, "headshot": false, "damage": 0}
	var headshot := allow_headshot and point.y >= global_position.y + lerpf(1.45, 0.75, crouch)
	var dmg := roundi(base_damage * (1.6 if headshot else 1.0))
	var new_hp := maxf(Game.hp_of(self) - float(dmg), 0.0)
	Game.set_hp(self, new_hp)
	var killed := new_hp <= 0.0
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
	if is_local():
		global_transform = _spawn_xform
		_yaw = rotation.y
		_pitch = 0.0
		head.rotation.x = 0.0
		weapon.visible = true
		weapon.refill()
		_apply_stance()
		health_changed.emit(hp, MAX_HP)
		respawned.emit()
	else:
		body_mesh.visible = true
		weapon.visible = false
		_apply_stance()


func spread_multiplier() -> float:
	if is_sprinting:
		return 4.2
	if crouch > 0.5:
		return 0.5
	var move := minf(Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 1.0)
	return 1.0 + move * 0.35


func _physics_process(delta: float) -> void:
	_spawn_protect = maxf(_spawn_protect - delta, 0.0)
	if not is_local():
		_apply_stance()
		body_mesh.visible = not is_dead
		collision_layer = 0 if is_dead else 2
		if nametag:
			nametag.text = display_name
		return
	var on_floor := is_on_floor()
	_update_stance(delta, on_floor)

	if not on_floor:
		velocity.y += float(get_gravity().y) * delta
	elif (not is_dead) and Input.is_action_just_pressed("jump"):
		if crouch > 0.2:
			if not _ceiling_blocked():
				crouch = 0.0
				_apply_stance()
				velocity.y = JUMP_SPEED
		else:
			velocity.y = JUMP_SPEED

	var input_vec := Vector2.ZERO
	if not is_dead:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	elif input_vec.length_squared() > 0.0001:
		wish = wish.normalized() * minf(input_vec.length(), 1.0)

	var wish_speed := WALK_SPEED
	is_sprinting = false
	if on_floor and (not is_dead) and crouch < 0.2 and Input.is_action_pressed("sprint") and wish.length_squared() > 0.04:
		wish_speed = SPRINT_SPEED
		is_sprinting = true
	elif crouch > 0.5:
		wish_speed = CROUCH_SPEED

	camera.extra_fov = SPRINT_FOV if is_sprinting else 0.0

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		horiz = _friction(horiz, delta)
		horiz = _accelerate(horiz, wish, wish_speed, GROUND_ACCEL, delta)
	else:
		horiz = _accelerate(horiz, wish, WALK_SPEED, AIR_ACCEL, delta)

	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()

	weapon.speed_factor = Vector2(velocity.x, velocity.z).length() / WALK_SPEED


func _update_stance(delta: float, _on_floor: bool) -> void:
	var want := (not is_dead) and Input.is_action_pressed("crouch")
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


func _friction(vel: Vector3, delta: float) -> Vector3:
	var speed := vel.length()
	if speed < 0.01:
		return Vector3.ZERO
	var control := STOP_SPEED if speed < STOP_SPEED else speed
	var drop := control * GROUND_FRICTION * delta
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
