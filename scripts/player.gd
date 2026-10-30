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
# Carry: surf speed survives the landing. Ground friction is 10, so an exit at 16 m/s would be
# gone in a fraction of a second. While carry is up and a move key is held, friction is 0.06:
# 16 m/s is still about 12.6 after CARRY_TIME (e^-0.24). Releasing move keys uses friction 6,
# so you can stop and shoot. The cap applies only when a boost is added, not every frame.
const CARRY_TIME := 4.0
const CARRY_ENTER_SPEED := 12.0 # just over sprint (11.4); a walk off a ramp does not start it
const CARRY_EXIT_BOOST := 2.0
const CARRY_FRICTION := 0.06
const CARRY_RELEASE_FRICTION := 6.0
const CARRY_MAX := 18.0
const STRIP_SPEED := 13.5 # sprint cannot cash a strip; the exit boost or a real surf can
const STRIP_BOOST := 2.5
const STRIP_COOLDOWN := 8.0
const STRIP_TELEPORT_M := 8.0 # a respawn skips the segment; a long frame at carry speed does not
const CARRY_FOV_MIN := 4.0
const CARRY_FOV_MAX := 8.0
const FOV_EXTRA_CAP := 10.0 # sprint FOV plus carry FOV, together
const WHOOSH := preload("res://assets/sounds/whoosh.wav")
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
var last_shot_ms := -100000 # ticks of this pawn's last shot seen here (minimap red dot)
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
var _kb_t := 0.0 # seconds of blast-push left: ground friction is low so the push carries
const KB_TIME := 0.45
const KB_FRICTION := 1.2 # ground friction while pushed (normal is Quake-style, much higher)
# --- Wallrun + wall jump (#80, Tony Hawk style) ---
# In the air, holding sprint and forward, touching a near-vertical wall while moving along it fast:
# glide along it for up to WALLRUN_TIME while slowly sinking. The same wall cannot be run again until
# you touch the ground or another wall; jump kicks you off it. At most WALLRUN_PER_AIR runs per jump.
const WALLRUN_TIME := 1.25
const WALLRUN_MIN_SPEED := 6.5 # m/s along the wall to start (sprint is 11.4, walk 7.6)
const WALLRUN_KEEP_SPEED := 3.5 # slower than this along the wall: drop off
const WALLRUN_SINK_START := 0.4 # m/s down at the start ...
const WALLRUN_SINK_END := 3.2 # ... and at the end of the run
const WALLRUN_RISE_DAMP := 18.0 # m/s² that bleeds a jump's upward speed into the run
const WALLRUN_MAX_NY := SURF_MIN_NORMAL_Y # flatter than this is a wall; surf ramps (0.05..0.7) never wallrun
const WALLRUN_PROBE := 0.75 # m from the body centre (capsule radius 0.4)
const WALLRUN_PER_AIR := 3
const WALLRUN_COYOTE := 0.15 # s after leaving the wall that a jump is still a wall jump
const WALLJUMP_PUSH := 6.5 # m/s away from the wall
const WALLJUMP_UP := 7.0
const WALLRUN_TILT := 0.16 # rad camera roll away from the wall
# --- Dive + roll (#81) ---
# Jump out of a slide (sprint + crouch, then jump) or press crouch in the air while holding sprint:
# a low forward dive. Landing from it rolls you forward without losing speed, then carry keeps it.
const DIVE_BOOST := 2.5
const DIVE_MAX := 15.0 # horizontal cap at the dive start (AIR_MAX_SPEED is 13.5, CARRY_MAX 18)
const DIVE_UP_GROUND := 4.8
const DIVE_UP_AIR := 2.0
const DIVE_MIN_SPEED := 6.0
const ROLL_TIME := 0.55
const ROLL_FRICTION := 0.25
const ROLL_CARRY := 1.5 # s of surf-style carry after the roll, so the speed survives it
const MOVE_NONE := 0
const MOVE_WALLRUN := 1
const MOVE_DIVE := 2
const MOVE_ROLL := 3
## Synced from the owner: what the pawn is doing (style tricks on the server, remote visuals).
@export var move_fx := MOVE_NONE
## Synced from the owner: +1 on every wall jump (the server sees the change: WALL JUMP KILL).
@export var walljumps := 0
var _wallrunning := false
var _wall_n := Vector3.ZERO
var _wall_key := "" # collider id + face of the current / last wall
var _wallrun_t := 0.0
var _wall_off_t := 10.0 # s since the last wallrun frame (coyote wall jump)
var _wallruns_air := 0
var _diving := false
var _dive_used := false # one dive per air time
var _roll_t := 0.0
var _roll_dir := Vector3.FORWARD
var _carry_t := 0.0 # seconds of surf-speed retention left (local sim only)
var _was_surfing := false
var _strip_cd: Dictionary = {} # strip name -> seconds until this pawn can take it again
var _strip_prev := Vector3.INF
var _whoosh: AudioStreamPlayer
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
var _run_t := 0.0 # s above Style.RUN_GUN_SPEED without stopping (RUN & GUN)
var _run_low_t := 0.0 # s below it since the last fast tick: past RUN_GUN_GRACE the run is over
var _wallrun_seen_t := -100.0 # match authority: last _style_clock with move_fx == MOVE_WALLRUN
var _walljump_seen_t := -100.0
var _walljumps_seen := -1
var _dive_seen_t := -100.0
var _roll_seen_t := -100.0
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
	if is_local():
		_whoosh = AudioStreamPlayer.new()
		_whoosh.stream = WHOOSH
		_whoosh.bus = "SFX"
		_whoosh.volume_db = -4.0
		add_child(_whoosh)
	call_deferred("_configure_control")


const ENEMY_SFX_NODES := [
	"Head/Camera3D/WeaponRoot/FireSfx", "Head/Camera3D/WeaponRoot/ReloadSfx", "StepSfx", "SlideSfx", "LandSfx",
]
var _bus_check_t := 0.0


## Enemy pawns play their shots and movement on the "Enemies" bus (own slider, #59). Teams can change
## mid-match, so this is re-checked twice a second rather than once at spawn.
func _tick_audio_bus(delta: float) -> void:
	_bus_check_t -= delta
	if _bus_check_t > 0.0:
		return
	_bus_check_t = 0.5
	var bus := "SFX"
	if not is_local() and not Game.is_dedicated:
		var me := Game.player_for_peer(multiplayer.get_unique_id())
		if me and Game.is_enemy(me, self):
			bus = "Enemies"
	for path in ENEMY_SFX_NODES:
		var n := get_node_or_null(path)
		if n and n.get("bus") != null and n.bus != bus:
			n.bus = bus


func _process(delta: float) -> void:
	_tick_audio_bus(delta)
	_update_nametag(delta)


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
		# Online the server's (deduplicated) name from the spawn data wins.
		if Game.player_name != "" and not Game.is_networked():
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
	if Game.chat_open or Game.pause_open or Game.killcam_active or Game.rc_view:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * Game.mouse_sens
		if weapon and weapon.is_ads():
			sens *= weapon.ads_sens_mult() # scope: Game.ads_sens (0.45); SMG iron sights: the zoom ratio
		# Invert Y flips the raw axis. No smoothing either way.
		var motion := event as InputEventMouseMotion
		var look_y := motion.relative.y
		if Game.invert_y:
			look_y = -look_y
		_yaw -= motion.relative.x * sens
		_pitch -= look_y * sens
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
	if event.is_action_pressed("grenade") and not is_dead and not Game.play_locked() and not Game.rc_view:
		_try_throw_grenade()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("throw_knife") and not is_dead and not Game.play_locked() and not Game.rc_view:
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
	var pal: Array = Game.COLORBLIND_TEAMS[Game.colorblind] if Game.colorblind > 0 else TEAM_COLORS
	return pal[clampi(team, 0, pal.size() - 1)]


## Team colour on a body material. Also used for the killcam ghosts.
static func paint_body(mat: StandardMaterial3D, team: int) -> void:
	var col: Color = team_color(team)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.45
	mat.emission_energy_multiplier = 0.7


## Blast push (Knockback). Runs on the machine that simulates this pawn.
func add_knockback(imp: Vector3) -> void:
	if is_dead:
		return
	velocity += imp
	_kb_t = KB_TIME
	_sliding = false
	if is_local() and camera:
		camera.add_shake(1.4, randf_range(-0.8, 0.8), 3.0)


## Maps over a drop (Skyline) set metadata kill_y on the map root: falling under it is a suicide.
func _check_kill_y() -> void:
	if is_dead or global_position.y >= Game.map_kill_y:
		return
	_spawn_protect = 0.0
	apply_hit(global_position, Vector3.UP, 10000.0, false, peer_id, &"fall")


## Damage is applied on the server (or offline). Clients get HP via broadcast_hurt.
## `headshot_mult` comes from the gun's WeaponDef (rifle 3.6, sniper 2.0, SMG 1.5, other guns 1.6).
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
	var old_hp := Game.hp_of(self)
	var new_hp := maxf(old_hp - float(dmg), 0.0)
	Game.set_hp(self, new_hp)
	Game.note_damage(killer_peer_id, peer_id, old_hp - new_hp)
	var killed := new_hp <= 0.0
	if killed:
		Game.register_kill(killer_peer_id, peer_id, weapon_id, headshot)
		Game.send_death_report(killer_peer_id, peer_id, weapon_id)
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
		camera.add_shake(0.85, randf_range(-0.35, 0.35), 2.2)
		if hurt_sfx.stream:
			hurt_sfx.pitch_scale = randf_range(0.92, 1.08)
			hurt_sfx.play()
		health_changed.emit(hp, MAX_HP)
	if killed:
		if not is_local():
			PhysFx.tumble(self, from_pos)
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	# The RC is gone with you, and it does not explode on the way out.
	if is_local() and Game.rc_view:
		RcXd.release_view()
	if Game._is_match_authority():
		RcXd.abort_for(peer_id)
	Game.killcam.note_death(peer_id)
	velocity = Vector3.ZERO
	_carry_t = 0.0
	_was_surfing = false
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
		# Show it now; the server still decides (count, death, freeze) and adopts this copy.
		var seq := 0
		if not Game.play_locked():
			seq = Game.predict_grenade(self, origin, dir)
		Game.request_grenade.rpc_id(1, origin, dir, seq)
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
		_check_kill_y()
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
	var chatting := Game.chat_open or Game.play_locked() or Game.rc_view
	_carry_t = maxf(_carry_t - delta, 0.0)
	_kb_t = maxf(_kb_t - delta, 0.0)
	_tick_strip_cd(delta)
	if Game.rc_view:
		_sliding = false
		velocity.x = 0.0
		velocity.z = 0.0
	var on_floor := is_on_floor()
	_try_start_slide(on_floor, chatting)
	_try_air_dive(on_floor, chatting)
	_update_stance(delta, on_floor)

	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if (not is_dead) and (not chatting) and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	var jumped := false
	if not on_floor:
		velocity.y += float(get_gravity().y) * delta
		_sliding = false
		if (_wallrunning or _wall_off_t <= WALLRUN_COYOTE) and (not is_dead) and (not chatting) and _jump_buffer > 0.0:
			_wall_jump()
			_jump_buffer = 0.0
	elif (not is_dead) and (not chatting) and _jump_buffer > 0.0 and _sliding:
		_sliding = false
		_start_dive(true) # sprint + crouch (slide), then jump: dive
		jumped = true
		_jump_buffer = 0.0
	elif (not is_dead) and (not chatting) and _jump_buffer > 0.0:
		_sliding = false
		_roll_t = 0.0
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

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if jumped or not on_floor:
		# The jump tick is already air: no ground friction, so sprint speed carries into the jump.
		horiz = _air_accelerate(horiz, wish, WALK_SPEED * minf(wish.length(), 1.0), delta)
	elif _kb_t > 0.0:
		horiz = _friction_amount(horiz, delta, KB_FRICTION)
		horiz = _accelerate(horiz, wish, wish_speed, GROUND_ACCEL * 0.5, delta)
	elif _carry_t > 0.0:
		# Held keys keep the surf speed. No keys: brake, so the next shot is a choice.
		var carry_friction := CARRY_FRICTION if wish.length_squared() > 0.04 else CARRY_RELEASE_FRICTION
		horiz = _friction_amount(horiz, delta, carry_friction)
		if not _sliding:
			horiz = _accelerate(horiz, wish, wish_speed, GROUND_ACCEL, delta)
	elif _roll_t > 0.0:
		horiz = _friction_amount(horiz, delta, ROLL_FRICTION) # the roll keeps the dive's speed
	elif _sliding:
		horiz = _friction_amount(horiz, delta, SLIDE_FRICTION)
	else:
		horiz = _friction(horiz, delta)
		horiz = _accelerate(horiz, wish, wish_speed, GROUND_ACCEL, delta)

	if _wallrunning:
		horiz = _wallrun_horiz(horiz, wish, delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if _wallrunning:
		var sink := lerpf(WALLRUN_SINK_START, WALLRUN_SINK_END, clampf(_wallrun_t / WALLRUN_TIME, 0.0, 1.0))
		# Gravity was added above; the wall replaces it. A jump's rise bleeds off instead of snapping.
		var vy := velocity.y - float(get_gravity().y) * delta
		velocity.y = move_toward(vy, -sink, WALLRUN_RISE_DAMP * delta) if vy > -sink else -sink
	_surf_t = maxf(_surf_t - delta, 0.0)
	if not on_floor and _surf_t > 0.0:
		velocity = clip_to_plane(velocity, _surf_normal)
	var pre_move := velocity
	move_and_slide()
	# Small lips (slab seams, curbs, ramp edges up to StepUp.MAX_HEIGHT) are walked over, not
	# a wall. Floor only: air strafing and surfing are untouched.
	if not jumped:
		_smooth_step(StepUp.try_step(self, pre_move, on_floor, delta))
	_note_surf_contact()
	# Landing is an air frame (no ground friction yet). Carry starts here, so the next
	# grounded frame keeps the speed instead of scrubbing it.
	var surfing := is_surfing()
	if _was_surfing and not surfing:
		_begin_carry()
	_was_surfing = surfing
	_boost_through_strips()
	_apply_carry_fov()
	_finish_slide()
	_tick_wallrun(delta, input_vec, chatting)
	_tick_dive_roll(delta)
	_tick_move_fx(delta)
	_tick_feet(delta)
	_tick_step_view(delta)

	weapon.speed_factor = Vector2(velocity.x, velocity.z).length() / WALK_SPEED


## A step-up moves the body up in one frame. The camera starts that much lower and catches up
## over a few frames, so a curb reads as a step and not a snap.
var _step_view := 0.0
const STEP_VIEW_RATE := 18.0


func _smooth_step(climb: float) -> void:
	if climb > 0.0 and camera:
		_step_view = clampf(_step_view - climb, -StepUp.MAX_HEIGHT, 0.0)


func _tick_step_view(delta: float) -> void:
	if camera == null:
		return
	if _step_view < 0.0:
		_step_view = minf(_step_view * exp(-STEP_VIEW_RATE * delta) + 0.0001, 0.0)
	camera.position.y = _step_view


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
## so the tag is no wallhack and the UAV streak (minimap) is still the way to find them.
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


func _try_start_slide(on_floor: bool, locked: bool) -> void:
	Movement.try_start_slide(self, on_floor, locked)


func _finish_slide() -> void:
	Movement.finish_slide(self)


func _update_stance(delta: float, _on_floor: bool) -> void:
	var want := _sliding or _diving or _roll_t > 0.0 or ((not is_dead) and (not Game.chat_open) and (not Game.rc_view) and Input.is_action_pressed("crouch"))
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


func _friction(vel: Vector3, delta: float) -> Vector3:
	return Movement.friction(vel, delta)


func _friction_amount(vel: Vector3, delta: float, friction: float) -> Vector3:
	return Movement.friction_amount(vel, delta, friction)


func _air_accelerate(vel: Vector3, wish: Vector3, wish_speed: float, delta: float) -> Vector3:
	return Movement.air_accelerate(vel, wish, wish_speed, delta)


## Source ClipVelocity: drop the part of `vel` that goes into the plane.
static func clip_to_plane(vel: Vector3, normal: Vector3) -> Vector3:
	var into := vel.dot(normal)
	if into >= 0.0:
		return vel
	return vel - normal * into


func _note_surf_contact() -> void:
	Movement.note_surf_contact(self)


func is_surfing() -> bool:
	return _surf_t > 0.0 and not is_on_floor()


func _begin_carry() -> void:
	Movement.begin_carry(self)


func _boost_through_strips() -> void:
	Movement.boost_through_strips(self)


func _tick_strip_cd(delta: float) -> void:
	Movement.tick_strip_cd(self, delta)


## Sprint FOV plus a bit more while carrying. ADS clears it. The two together stay within FOV_EXTRA_CAP.
func _apply_carry_fov() -> void:
	if weapon == null or camera == null:
		return
	if weapon.is_ads():
		camera.extra_fov = 0.0
		return
	var extra := SPRINT_FOV if is_sprinting else 0.0
	if _carry_t > 0.0:
		var speed := Vector2(velocity.x, velocity.z).length()
		extra += lerpf(CARRY_FOV_MIN, CARRY_FOV_MAX, clampf(speed / CARRY_MAX, 0.0, 1.0))
	camera.extra_fov = minf(extra, FOV_EXTRA_CAP)


## Strip boxes are scaled Node3Ds (group speed_strip). Local space is the unit cube around the origin.
static func segment_hits_strip(strip: Node3D, a: Vector3, b: Vector3) -> bool:
	if strip == null:
		return false
	var inv := strip.global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var t0 := 0.0
	var t1 := 1.0
	var delta := lb - la
	for axis in 3:
		var p := la[axis]
		var dir := delta[axis]
		if absf(dir) < 0.00001:
			if p < -0.5 or p > 0.5:
				return false
			continue
		var ta := (-0.5 - p) / dir
		var tb := (0.5 - p) / dir
		if ta > tb:
			var swap := ta
			ta = tb
			tb = swap
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


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
	# #84: every new move feeds the combo (worth nothing until a kill lands it).
	if move_fx == MOVE_WALLRUN:
		if _style_clock - _wallrun_seen_t > Style.MOVE_RECENT:
			var w2w := _style_clock - _walljump_seen_t <= Style.WALL_TO_WALL_WINDOW
			Game.combo_move(peer_id, Combo.WALL_TO_WALL if w2w else Combo.WALLRUN)
		_wallrun_seen_t = _style_clock
	elif move_fx == MOVE_DIVE:
		if _style_clock - _dive_seen_t > Style.MOVE_RECENT:
			Game.combo_move(peer_id, Combo.DIVE)
		_dive_seen_t = _style_clock
	elif move_fx == MOVE_ROLL:
		if _style_clock - _roll_seen_t > Style.MOVE_RECENT:
			Game.combo_move(peer_id, Combo.ROLL)
		_roll_seen_t = _style_clock
	if walljumps != _walljumps_seen:
		if _walljumps_seen >= 0:
			_walljump_seen_t = _style_clock
			Game.combo_move(peer_id, Combo.WALLJUMP)
		_walljumps_seen = walljumps
	_tick_combo_moves()
	if global_position.distance_to(_style_last_pos) > STYLE_TELEPORT_M:
		_style_in_air = false
		_landed_drop = 0.0
		air_time = 0.0
	_style_last_pos = global_position
	# A remote human's speed comes from snapshots, so one slow tick is not a stop; a real stop is longer.
	if _obs_speed >= Style.RUN_GUN_SPEED:
		_run_t += delta
		_run_low_t = 0.0
	else:
		_run_low_t += delta
		if _run_low_t > Style.RUN_GUN_GRACE:
			_run_t = 0.0
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


var _combo_surf := false
var _combo_slide := false
var _combo_air := false


## #84, match authority: surf, slide and long air as combo moves (rising edges only).
## Slides are not synced, so the server reads one from the synced crouch plus the observed speed.
func _tick_combo_moves() -> void:
	var surf := style_surfing()
	if surf and not _combo_surf:
		Game.combo_move(peer_id, Combo.SURF)
	_combo_surf = surf
	var slide := (not _style_in_air) and crouch > 0.6 and _obs_speed >= SPRINT_SPEED * 0.9 and move_fx != MOVE_ROLL
	if slide and not _combo_slide:
		Game.combo_move(peer_id, Combo.SLIDE)
	_combo_slide = slide
	var air := air_time >= Combo.AIR_TIME and not surf and move_fx == MOVE_NONE
	if air and not _combo_air:
		Game.combo_move(peer_id, Combo.AIR)
	_combo_air = air_time >= Combo.AIR_TIME


## Match authority (#80/#81): movement the server saw on this pawn just now (synced move_fx/walljumps).
func style_wallrun() -> bool:
	return _style_clock - _wallrun_seen_t <= Style.MOVE_RECENT


## A wall jump within WALLJUMP_RECENT, still in the air from it.
func style_walljump() -> bool:
	return _style_clock - _walljump_seen_t <= Style.WALLJUMP_RECENT and (_style_in_air or move_fx == MOVE_WALLRUN)


func style_dive() -> bool:
	return _style_clock - _dive_seen_t <= Style.MOVE_RECENT


func style_roll() -> bool:
	return _style_clock - _roll_seen_t <= Style.ROLL_RECENT


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
	_run_low_t = 0.0
	_style_in_air = false
	_landed_t = -100.0
	_surf_seen_t = -100.0
	_surf_t = 0.0
	_carry_t = 0.0
	_was_surfing = false
	_strip_cd.clear()
	_strip_prev = Vector3.INF
	_jump_buffer = 0.0
	_wallrunning = false
	_wall_key = ""
	_wall_off_t = 10.0
	_wallruns_air = 0
	_diving = false
	_dive_used = false
	_roll_t = 0.0
	move_fx = MOVE_NONE
	_wallrun_seen_t = -100.0
	_walljump_seen_t = -100.0
	_dive_seen_t = -100.0
	_roll_seen_t = -100.0
	_walljumps_seen = walljumps
	if camera:
		camera.move_pitch = 0.0
		camera.move_roll = 0.0


func _accelerate(vel: Vector3, wish: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	return Movement.accelerate(vel, wish, wish_speed, accel, delta)


# ---------------------------------------------------------------------------------------------
# Wallrun + wall jump (#80)


func is_wallrunning() -> bool:
	return _wallrunning


func _wallrun_horiz(horiz: Vector3, wish: Vector3, delta: float) -> Vector3:
	return Movement.wallrun_horiz(self, horiz, wish, delta)


func _find_wall() -> Dictionary:
	return Movement.find_wall(self)


func _tick_wallrun(delta: float, input_vec: Vector2, locked: bool) -> void:
	Movement.tick_wallrun(self, delta, input_vec, locked)


func _end_wallrun() -> void:
	Movement.end_wallrun(self)


func _wall_jump() -> void:
	Movement.wall_jump(self)


# ---------------------------------------------------------------------------------------------
# Dive + roll (#81)


func is_diving() -> bool:
	return _diving


func is_rolling() -> bool:
	return _roll_t > 0.0


func _try_air_dive(on_floor: bool, locked: bool) -> void:
	Movement.try_air_dive(self, on_floor, locked)


func _start_dive(from_ground: bool) -> void:
	Movement.start_dive(self, from_ground)


func _tick_dive_roll(delta: float) -> void:
	Movement.tick_dive_roll(self, delta)


## Synced state + the camera: tilt away from the wall, a forward flip while rolling.
func _tick_move_fx(delta: float) -> void:
	if _wallrunning:
		move_fx = MOVE_WALLRUN
	elif _diving:
		move_fx = MOVE_DIVE
	elif _roll_t > 0.0:
		move_fx = MOVE_ROLL
	else:
		move_fx = MOVE_NONE
	if camera == null:
		return
	var roll_target := 0.0
	if _wallrunning:
		var right := transform.basis.x
		roll_target = -signf(right.dot(_wall_n)) * WALLRUN_TILT * Game.shake_scale()
	camera.move_roll = lerpf(camera.move_roll, roll_target, 1.0 - exp(-10.0 * delta))
	if _roll_t > 0.0:
		var p := 1.0 - _roll_t / ROLL_TIME
		if Game.shake_scale() >= 0.5:
			camera.move_pitch = -TAU * ease(p, -1.8) # full forward flip
		else:
			camera.move_pitch = -deg_to_rad(25.0) * sin(p * PI) # reduced motion: a dip
	elif _diving:
		camera.move_pitch = lerpf(camera.move_pitch, -0.12, 1.0 - exp(-8.0 * delta))
	else:
		camera.move_pitch = lerpf(wrapf(camera.move_pitch, -PI, PI), 0.0, 1.0 - exp(-14.0 * delta))
