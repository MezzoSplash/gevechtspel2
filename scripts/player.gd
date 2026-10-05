class_name Player
extends CharacterBody3D
## Human or bot pawn. Same scene, same guns, same movement.
## Bots: `is_bot`, negative `peer_id`, server authority. Humans: authority = peer_id.

signal health_changed(hp: float, max_hp: float)
signal died
signal respawned
signal damage_from(pos: Vector3) # local pawn took damage from there (HUD direction indicator)

const WALK_SPEED := 7.6
const SPRINT_SPEED := 11.4
const CROUCH_SPEED := 3.5
const GROUND_ACCEL := 14.0
const GROUND_FRICTION := 10.0
const JUMP_SPEED := 7.6
# --- Air control, Source / CS:GO style (humans; bots keep BOT_AIR_ACCEL) ---
# In the air the wish speed is capped at AIR_WISH_CAP, so holding W adds almost nothing, but strafing
# (A/D) while turning the mouse the same way keeps bending the velocity and adds a little speed.
const AIR_ACCEL := 12.0 # sv_airaccelerate: how fast the capped wish speed is reached
const AIR_WISH_CAP := 1.1 # m/s (Source's 30 u/s, at our 1.6x movement scale)
const AIR_MAX_SPEED := 13.5 # strafing cannot push horizontal speed past this (sprint is 11.4)
const BOT_AIR_ACCEL := 3.5 # bots never strafe-jump; they keep the old direct air control
const JUMP_BUFFER := 0.1 # seconds a jump press is kept, so a hop on landing is not eaten
# Surfing: a slope steeper than floor_max_angle (45°) is not floor. While touching one, the velocity is
# clipped along its plane (Source ClipVelocity): gravity turns into speed along the ramp, strafing steers.
const SURF_MIN_NORMAL_Y := 0.05 # flatter than a wall
const SURF_MAX_NORMAL_Y := 0.7 # steeper than walkable (cos 45° = 0.707)
const SURF_MEMORY := 0.1 # seconds a ramp contact is kept between frames
const SURF_PROBE := 0.12 # m: while surfing, look this far into the ramp so a clean glide keeps contact
const MOUSE_SENS := 0.00135
const MAX_PITCH := 1.5359
const STOP_SPEED := 1.5
const MAX_HP := 100.0
const RESPAWN_TIME := 2.0
const STAND_CAPSULE := 1.8
const CROUCH_CAPSULE := 1.0
const STAND_EYE := 1.6
const CROUCH_EYE := 0.88
# Drawn head sits on the movement capsule. The ray hits that shell, not the mesh.
const HEAD_STAND_Y := 1.52
const HEAD_CROUCH_Y := 0.78
const HEAD_HIT_R := 0.41
const CROUCH_BLEND := 12.0
const SPRINT_FOV := 6.0
const SPAWN_PROTECT := 1.8
const SLIDE_MIN := 0.35
const SLIDE_FRICTION := 2.4
const REGEN_DELAY := 4.5 # seconds without damage before health comes back
const REGEN_RATE := 12.0 # HP per second, up to MAX_HP
const TAG_CHECK := 0.1 # seconds between nametag line-of-sight rays

@onready var head: Node3D = $Head
@onready var camera: CameraFeel = $Head/Camera3D
@onready var weapon: Weapon = $Head/Camera3D/WeaponRoot
@onready var body_mesh: Node3D = $BodyMesh
@onready var hurt_sfx: AudioStreamPlayer = $HurtSfx
@onready var step_sfx: AudioStreamPlayer3D = $StepSfx
@onready var land_sfx: AudioStreamPlayer3D = $LandSfx
@onready var slide_sfx: AudioStreamPlayer3D = $SlideSfx
@onready var col_shape: CollisionShape3D = $CollisionShape3D
@onready var nametag: Label3D = $Nametag

const TEAM_COLORS := [Color(0.25, 0.55, 0.95), Color(0.92, 0.38, 0.22)]
const FFA_COLOR := Color(0.86, 0.24, 0.32) # FFA: everyone is an enemy, so one colour for all
const SELF_COLOR := Color(1.0, 0.82, 0.3) # FFA: your own name in feed/board
const Brain := preload("res://scripts/bot_brain.gd")
## Concrete footsteps (Kenney, CC0). A different one each step, never the same twice in a row.
const STEP_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/step.wav"),
	preload("res://assets/sounds/step_1.wav"),
	preload("res://assets/sounds/step_2.wav"),
	preload("res://assets/sounds/step_3.wav"),
	preload("res://assets/sounds/step_4.wav"),
]

const GRENADE_MAX := 2 # bots; humans get their class's count

var hp := MAX_HP
var grenades := GRENADE_MAX
var knives := 0 # throwing knives (grenade slot, F); bots carry none
@export var peer_id := 0
@export var is_dead := false
@export var is_bot := false
@export var team_id := 0
@export var loadout_index := 0 # bots: armory index of their one gun
## Humans, on the authority and the owner: validated class loadout (PlayerClasses.parse_loadout).
## Empty = bot or a remote copy: full armory, GRENADE_MAX.
var loadout: Dictionary = {}
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
var _radar_mark: MeshInstance3D
var _sliding := false
var _slide_t := 0.0
var _slide_dir := Vector3.FORWARD
var _step_t := 0.0
var _step_last := -1
var _feet_last := Vector3.ZERO
var _was_air := false
var since_hurt := 0.0 # match authority only: seconds since the last damage (regen gate)
var _tag_show := false # nametag allowed (teammate, or enemy in line of sight)
var _tag_check_t := 0.0
var _obs_speed := 0.0 # smoothed ground speed from position deltas (server's view of remote humans)
var _jump_buffer := 0.0
var _surf_normal := Vector3.ZERO # last steep ramp touched (Vector3.ZERO: none)
var _surf_t := 0.0
# Style tracking, match authority only (Style / Game.register_kill): turn history and time in the air.
var air_time := 0.0 # seconds with free space under the feet
var _style_clock := 0.0
var _yaw_samples: Array = [] # [[t, signed yaw delta rad], ...] over the last STYLE_KEEP seconds
var _style_last_yaw := 0.0
var _style_has_yaw := false
var _style_in_air := false
var _fall_peak := 0.0 # highest y since the feet left the ground
var _landed_drop := 0.0 # metres of the last fall, from its peak
var _landed_t := -100.0
var _surf_seen_t := -100.0 # last _style_clock with a steep ramp beside or under us
var _style_last_pos := Vector3.INF # teleports (respawn, admin moves) never count as a fall
var _run_t := 0.0 # s above Style.RUN_GUN_SPEED without a dip (RUN & GUN)
const STYLE_KEEP := 1.5
const STYLE_RAMP_REACH := 1.0 # m from the body centre (capsule radius ~0.45, plus slack)
const STYLE_TELEPORT_M := 3.0 # one tick moving further than this is a teleport (snapshots move < 1 m)


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
	_yaw = rotation.y # Orange spawns turned 180°; the first mouse move must not snap back
	_capsule = col_shape.shape.duplicate() as CapsuleShape3D
	col_shape.shape = _capsule
	if peer_id == 0:
		peer_id = _owner_peer()
	_dup_body_mat()
	_apply_team_visual()
	_init_loadout()
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


## Team radar: on this machine, while Game.radar_left runs, every living pawn not on
## Game.radar_team shows its marker (FFA: every other pawn; only the activator's machine has
## radar_left). Machines without a running radar keep them hidden.
func _update_radar_mark() -> void:
	if _radar_mark == null:
		return
	var hostile := team_id != Game.radar_team or Game.is_ffa()
	var on := Game.radar_left > 0.0 and not is_dead and hostile and not is_local()
	if on == _radar_mark.visible:
		return
	if on:
		var mat := _radar_mark.material_override as StandardMaterial3D
		if mat:
			var col: Color = team_color(team_id)
			mat.albedo_color = col
			mat.emission = col
	_radar_mark.visible = on


func _process(delta: float) -> void:
	_update_nametag(delta)
	_update_radar_mark()


## Server: what this peer picked (or the default). Owner: what the server last confirmed.
func _init_loadout() -> void:
	if is_bot or peer_id < 0:
		return
	if Game._is_match_authority():
		loadout = Game.loadouts.spawn_loadout(peer_id)
	elif is_local():
		var mine := Game.loadouts.mine
		loadout = mine.duplicate(true) if not mine.is_empty() else PlayerClasses.default_loadout()
	else:
		return
	apply_loadout()


func weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if loadout.is_empty():
		for w in Weapon.LOADOUT:
			ids.append(w.id)
		return ids
	ids.append(StringName(loadout.primary))
	ids.append(StringName(loadout.secondary))
	return ids


## Server fire/switch check. Remote copies (empty loadout) say yes; they never validate anything.
func has_weapon(id: StringName) -> bool:
	return weapon_ids().has(id)


## Per type in the class (frags on G, knives on F); the class shares PlayerClasses.MAX_GRENADES slots.
func grenade_max() -> int:
	if loadout.is_empty():
		return GRENADE_MAX
	var g: Dictionary = loadout.get("grenades", {})
	return clampi(int(g.get("frag", 0)), 0, PlayerClasses.MAX_GRENADES)


func knife_max() -> int:
	if loadout.is_empty():
		return 0
	var g: Dictionary = loadout.get("grenades", {})
	return clampi(int(g.get("knife", 0)), 0, PlayerClasses.MAX_GRENADES)


## Carry the class's guns (holding the primary), full ammo, class grenades.
func apply_loadout() -> void:
	if weapon:
		weapon.set_slots(weapon_ids())
		weapon.refill()
	grenades = grenade_max()
	knives = knife_max()
	_notify_grenades()


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
		set_display_name(display_name)
		_update_nametag(0.0, true)


func make_active_camera() -> void:
	var menu_cam := get_tree().get_first_node_in_group("menu_camera") as Camera3D
	if menu_cam:
		menu_cam.current = false
	camera.current = true


func _input(event: InputEvent) -> void:
	if not is_local():
		return
	if Game.chat_open or Game.pause_open or Game.killcam_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * Game.mouse_sens
		if weapon and weapon.is_ads():
			sens *= weapon.ads_sens_mult() # scope: Game.ads_sens (0.45); SMG iron sights: the zoom ratio
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
	if event.is_action_pressed("grenade") and not is_dead and not Game.play_locked():
		_try_throw_grenade()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("throw_knife") and not is_dead and not Game.play_locked():
		_try_throw_knife()
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
		nametag.modulate = team_color(team_id)


func _dup_body_mat() -> void:
	if body_mesh == null:
		return
	var src_mesh := body_mesh.get_node_or_null("Torso") as MeshInstance3D
	var src: Material = src_mesh.get_active_material(0) if src_mesh else null
	if src is StandardMaterial3D:
		_body_mat = (src as StandardMaterial3D).duplicate()
	else:
		_body_mat = StandardMaterial3D.new()
	for child in body_mesh.get_children():
		var part := child as MeshInstance3D
		if part:
			part.set_surface_override_material(0, _body_mat)
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_team_visual() -> void:
	var col: Color = team_color(team_id)
	if _body_mat:
		paint_body(_body_mat, team_id)
	if nametag:
		nametag.modulate = col


## Body/tag/feed colour of a team. FFA has no teams: everyone gets FFA_COLOR.
static func team_color(team: int) -> Color:
	if Game.is_ffa():
		return FFA_COLOR
	return TEAM_COLORS[clampi(team, 0, TEAM_COLORS.size() - 1)]


## Team colour on a body material. Also used for the killcam ghosts.
static func paint_body(mat: StandardMaterial3D, team: int) -> void:
	var col: Color = team_color(team)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.45
	mat.emission_energy_multiplier = 0.7


## Damage is applied on the server (or offline). Clients get HP via broadcast_hurt.
## `headshot_mult` comes from the gun's WeaponDef (sniper 2.0, others 1.6).
## Grenades pass allow_headshot false. The test uses the drawn head, not a height band.
func apply_hit(
	point: Vector3,
	_normal: Vector3,
	base_damage: float,
	allow_headshot: bool = true,
	killer_peer_id: int = 0,
	weapon_id: StringName = &"rifle",
	headshot_mult: float = 1.6,
	source_pos: Vector3 = Vector3.INF
) -> Dictionary:
	if is_dead or _spawn_protect > 0.0 or Game.killcam_active:
		return {"killed": false, "headshot": false, "damage": 0}
	if Game.is_networked() and not multiplayer.is_server():
		return {"killed": false, "headshot": false, "damage": 0}
	var headshot := allow_headshot and _point_hits_head(point)
	var dmg := roundi(base_damage * (headshot_mult if headshot else 1.0))
	if dmg > 0:
		since_hurt = 0.0
	var new_hp := maxf(Game.hp_of(self) - float(dmg), 0.0)
	Game.set_hp(self, new_hp)
	var killed := new_hp <= 0.0
	if killed:
		Game.register_kill(killer_peer_id, peer_id, weapon_id, headshot)
	if dmg <= 0:
		source_pos = Vector3.INF
	elif not source_pos.is_finite():
		var attacker := Game.player_for_peer(killer_peer_id)
		if attacker and attacker != self:
			source_pos = attacker.global_position
	if Game.is_networked():
		Game.broadcast_hurt.rpc(peer_id, new_hp, killed, source_pos)
	else:
		apply_hurt_state(new_hp, killed, source_pos)
	return {"killed": killed, "headshot": headshot, "damage": dmg}


## True when the capsule hit lands on the drawn head, including while crouched.
func _point_hits_head(point: Vector3) -> bool:
	var center := global_position + Vector3(0.0, lerpf(HEAD_STAND_Y, HEAD_CROUCH_Y, crouch), 0.0)
	var mark := body_mesh.get_node_or_null("HeadHit") if body_mesh else null
	if mark is Node3D:
		center = (mark as Node3D).global_position
	return point.distance_to(center) <= HEAD_HIT_R


## `from_pos`: damage source for the HUD direction indicator (Vector3.INF = unknown).
func apply_hurt_state(new_hp: float, killed: bool, from_pos: Vector3 = Vector3.INF) -> void:
	hp = new_hp
	if not killed:
		Game.killcam.note_hurt(peer_id)
	if is_local() and from_pos.is_finite():
		damage_from.emit(from_pos)
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
	Game.killcam.note_death(peer_id)
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
	Game.respawn_pawn(self)


func apply_respawn_state() -> void:
	hp = MAX_HP
	# Round-start respawns come through here too; the server's HP copy must reset with them.
	if Game._is_match_authority():
		Game.set_hp(self, MAX_HP)
	is_dead = false
	_spawn_protect = SPAWN_PROTECT
	collision_layer = 2
	velocity = Vector3.ZERO
	crouch = 0.0
	is_sprinting = false
	global_transform = _spawn_xform
	_yaw = rotation.y
	_pitch = 0.0
	_reset_style_track()
	head.rotation.x = 0.0
	weapon.visible = true
	if not loadout.is_empty() and weapon:
		weapon.set_slots(weapon_ids()) # spawn holding the primary
	grenades = grenade_max()
	knives = knife_max()
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


## F. The knife leaves from the right hand, a little lower than the eye, along the crosshair.
func _try_throw_knife() -> void:
	if knives <= 0 or camera == null or (weapon and weapon.is_throwing()):
		return
	var origin := camera.global_position + (-camera.global_basis.z) * 0.5 + camera.global_basis.x * 0.12
	var dir := -camera.global_basis.z
	if weapon:
		weapon.play_throw()
	if Game.is_networked() and not multiplayer.is_server():
		Game.request_knife.rpc_id(1, origin, dir)
	else:
		Game.throw_knife(self, origin, dir)


func _notify_grenades() -> void:
	if not is_local():
		return
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_grenades(grenades, knives)


## Held gun's movement speed factor (SMG 1.08). Bots use it too.
func gun_speed_mult() -> float:
	if weapon == null or weapon.def == null:
		return 1.0
	return weapon.def.move_speed_mult


## Match authority: seconds this pawn has stayed above Style.RUN_GUN_SPEED (0 after any dip).
func run_time() -> float:
	return _run_t


## Server floor for a remote human's claimed spread: half the walk penalty at the speed we see them move.
## Lenient on purpose (sync lag), it only stops "always standing still" clients.
func min_spread_multiplier() -> float:
	return 1.0 + minf(_obs_speed / WALK_SPEED, 1.0) * 1.15 * 0.5


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
	if Game._is_match_authority():
		_tick_style_track(delta)
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
	var chatting := Game.chat_open or Game.play_locked()
	var on_floor := is_on_floor()
	_try_start_slide(on_floor, chatting)
	_update_stance(delta, on_floor)

	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if (not is_dead) and (not chatting) and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	var jumped := false
	if not on_floor:
		velocity.y += float(get_gravity().y) * delta
		_sliding = false
	elif (not is_dead) and (not chatting) and _jump_buffer > 0.0:
		_sliding = false
		if crouch > 0.2:
			if not _ceiling_blocked():
				crouch = 0.0
				_apply_stance()
				velocity.y = JUMP_SPEED
				jumped = true
		else:
			velocity.y = JUMP_SPEED
			jumped = true
		if jumped:
			_jump_buffer = 0.0

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
	if not _sliding:
		wish_speed *= gun_speed_mult()

	camera.extra_fov = 0.0 if weapon.is_ads() else (SPRINT_FOV if is_sprinting else 0.0)

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if jumped or not on_floor:
		# The jump tick is already air: no ground friction, so sprint speed carries into the jump.
		horiz = _air_accelerate(horiz, wish, WALK_SPEED * minf(wish.length(), 1.0), delta)
	elif _sliding:
		horiz = _friction_amount(horiz, delta, SLIDE_FRICTION)
	else:
		horiz = _friction(horiz, delta)
		horiz = _accelerate(horiz, wish, wish_speed, GROUND_ACCEL, delta)

	velocity.x = horiz.x
	velocity.z = horiz.z
	_surf_t = maxf(_surf_t - delta, 0.0)
	if not on_floor and _surf_t > 0.0:
		velocity = clip_to_plane(velocity, _surf_normal)
	move_and_slide()
	_note_surf_contact()
	_finish_slide()
	_tick_feet(delta)

	weapon.speed_factor = Vector2(velocity.x, velocity.z).length() / WALK_SPEED


## Uses velocity when we simulate, otherwise position delta (puppets have velocity zeroed).
func _tick_feet(delta: float) -> void:
	var moved := global_position - _feet_last
	var inst_speed := minf(Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001), SPRINT_SPEED * 1.5)
	_obs_speed = lerpf(_obs_speed, inst_speed, 0.15)
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
	var pick := randi() % (STEP_SOUNDS.size() - 1)
	if pick >= _step_last:
		pick += 1
	_step_last = pick
	step_sfx.stream = STEP_SOUNDS[pick]
	step_sfx.pitch_scale = randf_range(0.92, 1.08)
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
		nametag.text = display_name


## Where bots aim: chest height of the current stance (crouch is 1.0 m tall, not 1.8).
func aim_point() -> Vector3:
	return global_position + Vector3(0.0, lerpf(1.05, 0.6, crouch), 0.0)


## Centre of the drawn head for this stance.
func head_point() -> Vector3:
	return global_position + Vector3(0.0, lerpf(HEAD_STAND_Y, HEAD_CROUCH_Y, crouch), 0.0)


## Regen tick from the match authority (Game._tick_regen / sync_regen). No hurt flash or sound.
func apply_regen_hp(new_hp: float) -> void:
	if is_dead:
		return
	hp = new_hp
	if is_local():
		health_changed.emit(hp, MAX_HP)


## Teammates keep their tag through walls (where is my team). Enemies only show it in line of sight,
## so the tag is no wallhack and the radar streak is still the way to find them.
func _update_nametag(delta: float, force: bool = false) -> void:
	if nametag == null or is_local():
		return
	if Game.is_dedicated or DisplayServer.get_name() == "headless":
		nametag.visible = false
		return
	_tag_check_t -= delta
	if force or _tag_check_t <= 0.0:
		_tag_check_t = TAG_CHECK + randf() * 0.03 # spread the rays over frames
		var me := Game.player_for_peer(multiplayer.get_unique_id())
		var mate := me != null and not Game.is_enemy(self, me)
		nametag.no_depth_test = mate
		_tag_show = mate or _enemy_in_sight()
	nametag.visible = _tag_show and not is_dead


## World-only rays (players do not block) from the active camera to the head and the chest.
func _enemy_in_sight() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	for to in [head_point(), aim_point()]:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		if space.intersect_ray(query).is_empty():
			return true
	return false


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
	_pose_figure()


func _pose_figure() -> void:
	pose_body(body_mesh, crouch)


## Crouch lowers the torso, arms, and head together. The head marker is the hit target.
## Static so the killcam ghosts (a copy of BodyMesh) crouch the same way.
static func pose_body(body: Node3D, crouch_amt: float) -> void:
	if body == null:
		return
	var head_y := lerpf(HEAD_STAND_Y, HEAD_CROUCH_Y, crouch_amt)
	var torso := body.get_node_or_null("Torso") as MeshInstance3D
	var head_mesh := body.get_node_or_null("HeadMesh") as MeshInstance3D
	var arm_l := body.get_node_or_null("ArmL") as MeshInstance3D
	var arm_r := body.get_node_or_null("ArmR") as MeshInstance3D
	var hit := body.get_node_or_null("HeadHit") as Node3D
	if torso:
		torso.position.y = lerpf(0.86, 0.50, crouch_amt)
		torso.scale.y = lerpf(1.0, 0.62, crouch_amt)
	if head_mesh:
		head_mesh.position.y = head_y
	if arm_l:
		arm_l.position.y = lerpf(1.02, 0.58, crouch_amt)
	if arm_r:
		arm_r.position.y = lerpf(1.02, 0.58, crouch_amt)
	if hit:
		hit.position.y = head_y


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


## Source AirAccelerate: the speed we may add along the wish direction is capped at AIR_WISH_CAP, the
## rate is not. Straight ahead adds nothing once you move; perpendicular (strafe + mouse) bends the
## velocity and adds a little speed, bounded by AIR_MAX_SPEED (speed you already had is kept).
func _air_accelerate(vel: Vector3, wish: Vector3, wish_speed: float, delta: float) -> Vector3:
	if wish.length_squared() < 0.0001 or wish_speed <= 0.0:
		return vel
	var dir := wish.normalized()
	var add := minf(wish_speed, AIR_WISH_CAP) - vel.dot(dir)
	if add <= 0.0:
		return vel
	var before := vel.length()
	var out := vel + dir * minf(AIR_ACCEL * wish_speed * delta, add)
	var limit := maxf(before, AIR_MAX_SPEED)
	var speed := out.length()
	if speed > limit:
		out *= limit / speed
	return out


## Source ClipVelocity: drop the part of `vel` that goes into the plane.
static func clip_to_plane(vel: Vector3, normal: Vector3) -> Vector3:
	var into := vel.dot(normal)
	if into >= 0.0:
		return vel
	return vel - normal * into


## Remember a steep ramp we touched this frame (not floor, not a wall): surfing clips against it.
func _note_surf_contact() -> void:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y > SURF_MIN_NORMAL_Y and n.y < SURF_MAX_NORMAL_Y:
			_surf_normal = n
			_surf_t = SURF_MEMORY
			return
	# A clipped glide runs parallel to the ramp, so move_and_slide may not touch it every frame.
	if _surf_t > 0.0 and not is_on_floor():
		var hit := KinematicCollision3D.new()
		if test_move(global_transform, -_surf_normal * SURF_PROBE, hit):
			var n2 := hit.get_normal()
			if n2.y > SURF_MIN_NORMAL_Y and n2.y < SURF_MAX_NORMAL_Y:
				_surf_normal = n2
				_surf_t = SURF_MEMORY


func is_surfing() -> bool:
	return _surf_t > 0.0 and not is_on_floor()


## Match authority, every pawn: turn history (for 360s) and time with free space under the feet
## (for airshots). Works from the pawn's position/rotation, so remote humans count the same as bots.
func _tick_style_track(delta: float) -> void:
	_style_clock += delta
	var yaw := rotation.y
	if _style_has_yaw:
		var d := wrapf(yaw - _style_last_yaw, -PI, PI)
		if absf(d) > 0.00001:
			_yaw_samples.append([_style_clock, d])
	_style_last_yaw = yaw
	_style_has_yaw = true
	while not _yaw_samples.is_empty() and float(_yaw_samples[0][0]) < _style_clock - STYLE_KEEP:
		_yaw_samples.pop_front()
	if is_dead or not is_inside_tree():
		air_time = 0.0
		_style_in_air = false
		return
	if global_position.distance_to(_style_last_pos) > STYLE_TELEPORT_M:
		_style_in_air = false
		_landed_drop = 0.0
		air_time = 0.0
	_style_last_pos = global_position
	_run_t = _run_t + delta if _obs_speed >= Style.RUN_GUN_SPEED else 0.0
	var under := _feet_ray()
	# Nothing under the feet, or only a ramp too steep to stand on: in the air (surfing counts).
	var steep := not under.is_empty() and float((under.normal as Vector3).y) < Player.SURF_MAX_NORMAL_Y
	if under.is_empty() or steep:
		air_time += delta
		var y := global_position.y
		if not _style_in_air:
			_style_in_air = true
			_fall_peak = y
		_fall_peak = maxf(_fall_peak, y)
		if steep or _ramp_beside():
			_surf_seen_t = _style_clock
			_fall_peak = y # riding a ramp is not falling: DROP counts the free fall after it
	else:
		if _style_in_air:
			_landed_drop = _fall_peak - global_position.y
			_landed_t = _style_clock
		_style_in_air = false
		air_time = 0.0


func _feet_ray() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.05, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, global_position - Vector3(0.0, Style.AIR_GAP, 0.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


## In the air: a surf ramp (steeper than walkable, not a wall) touching the capsule's side?
## Eight rays from the body centre, angled down like the contact normal on a 45-85° ramp.
func _ramp_beside() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.9, 0.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a)) * 0.82 + Vector3(0.0, -0.57, 0.0) # ~35° down
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * STYLE_RAMP_REACH)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var ny := float((hit.normal as Vector3).y)
		if ny > SURF_MIN_NORMAL_Y and ny < SURF_MAX_NORMAL_Y:
			return true
	return false


## Match authority: surfing right now (or within Style.SURF_RECENT).
func style_surfing() -> bool:
	return _style_in_air and _style_clock - _surf_seen_t <= Style.SURF_RECENT


## Match authority: how far we fell, while falling or just after landing (0 otherwise).
func style_drop() -> float:
	if _style_in_air:
		return maxf(_fall_peak - global_position.y, 0.0)
	if _style_clock - _landed_t <= Style.DROP_RECENT:
		return maxf(_landed_drop, 0.0)
	return 0.0


## Largest one-way turn in degrees during the last `window` seconds (match authority).
func spin_degrees(window: float = Style.SPIN_WINDOW) -> float:
	return Style.spin_degrees(_yaw_samples, _style_clock, window)


func _reset_style_track() -> void:
	_style_last_pos = Vector3.INF
	_yaw_samples.clear()
	_style_has_yaw = false
	air_time = 0.0
	_run_t = 0.0
	_style_in_air = false
	_landed_t = -100.0
	_surf_seen_t = -100.0
	_surf_t = 0.0
	_jump_buffer = 0.0


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
