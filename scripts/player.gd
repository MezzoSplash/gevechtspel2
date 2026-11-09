class_name Player
extends CharacterBody3D
## Human or bot pawn. Same scene, same guns, same movement.
## Bots: `is_bot`, negative `peer_id`, server authority. Humans: authority = peer_id.

signal health_changed(hp: float, max_hp: float)
signal armour_changed(armour: float)
signal died
signal respawned
signal damage_from(pos: Vector3) # local pawn took damage from there (HUD direction indicator)

const WALK_SPEED := 7.6
const SPRINT_SPEED := 11.4
## Movement spread ladder. One source: the server's floor, the client's own value and
## Game.SPREAD_MAX all read these, so a change cannot drift between client and server.
const SPREAD_WALK_K := 1.15
const SPREAD_SPRINT := 6.0
const SPREAD_SLIDE := 8.0
const CROUCH_SPEED := 3.5
const GROUND_ACCEL := 14.0
const GROUND_FRICTION := 10.0
const JUMP_SPEED := 7.6
# --- Air control, Source / CS:GO style (humans; bots keep BOT_AIR_ACCEL) ---
# In the air the wish speed is capped at AIR_WISH_CAP, so holding W adds almost nothing, but strafing
# (A/D) while turning the mouse the same way keeps bending the velocity and adds a little speed.
const AIR_ACCEL := 12.0 # sv_airaccelerate: how fast the capped wish speed is reached
const AIR_WISH_CAP := 1.25 # floaty pass: was 1.1; m/s (Source's 30 u/s, at our 1.6x movement scale)
const AIR_MAX_SPEED := 13.5 # strafing cannot push horizontal speed past this (sprint is 11.4)
# #152: light mid-air steering. Holding a direction turns the horizontal velocity toward it, at most
# AIR_STEER_RATE rad/s, without adding speed (not a jetpack). Beyond AIR_STEER_MAX_ANGLE (e.g. holding S)
# nothing happens, so you cannot flip around mid-air. 0.0 turns it off.
const AIR_STEER_RATE := 1.4 # rad/s at full input (~80 deg/s; floaty pass: was 1.2)
const AIR_STEER_MAX_ANGLE := deg_to_rad(100.0)
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
# --- Speed FX (Game.speed_fx, local player only) ---
# Everything here scales with the player's own horizontal speed, so going fast is felt and not only
# seen. Only `extra_fov` and `camera.move_pitch` are touched: the hip FOV (Game.fov) and the ADS FOV
# stay where they are, so aiming is untouched. With the toggle off the old sprint + carry FOV stack
# runs instead (see _apply_carry_fov), and no dip, lines or wind.
const SPEED_FOV_REF := SPRINT_SPEED # 11.4 m/s: the kick starts here
const SPEED_FOV_EPS := 0.05 # m/s: float32 slack on the SPRINT_SPEED boundary
const SPEED_FOV_FULL := CARRY_MAX # 18.0 m/s: full kick
const SPEED_FOV_AT_SPRINT := 4.0 # degrees extra_fov at exactly SPEED_FOV_REF
const SPEED_FOV_MAX := 10.0 # degrees extra_fov at SPEED_FOV_FULL (FOV_EXTRA_CAP still caps it)
const SPEED_LINES_START := 12.0 # m/s: speed lines start showing
const SPEED_LINES_FULL := 16.5 # m/s: full intensity
const SPEED_LINES_SMOOTH := 8.0 # exp rate the overlay eases toward its target intensity
const LAND_CAM_MIN_SPEED := 5.0 # m/s falling: below this a landing is not worth a dip
const LAND_CAM_DIP_MAX := 0.08 # rad: deepest landing camera dip
const LAND_CAM_DIP_PER_MS := 0.012 # rad per m/s of fall speed above LAND_CAM_MIN_SPEED
const LAND_CAM_RECOVER := 10.0 # exp rate of the dip easing back to 0
const WIND_START := 11.4 # m/s: wind becomes audible
const WIND_FULL := 17.0 # m/s: full wind
const WIND_VOL_DB_MIN := -28.0
const WIND_VOL_DB_MAX := -8.0
const WIND_PITCH_MIN := 0.85
const WIND_PITCH_MAX := 1.25
const WHOOSH := preload("res://assets/sounds/whoosh.wav")
const WIND_LOOP := preload("res://assets/sounds/wind_loop.wav")
const REGEN_DELAY := 4.5 # seconds without damage before health comes back
const REGEN_RATE := 12.0 # HP per second, up to MAX_HP
const TAG_CHECK := 0.1 # seconds between nametag line-of-sight rays

@onready var head: Node3D = $Head
@onready var camera: CameraFeel = $Head/Camera3D
@onready var weapon: Weapon = $Head/Camera3D/WeaponRoot
@onready var body_mesh: Node3D = $BodyMesh
@onready var hurt_sfx: AudioStreamPlayer = $HurtSfx
@onready var pickup_sfx: AudioStreamPlayer = $PickupSfx
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
var armour := 0.0 # Schildplaat (#144): damage comes off this before HP
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
var los_coast := false # LOS: this pawn keeps the line it already had; the hands are the camera
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
## Extra horizontal speed a dive adds (m/s). Floaty pass: was 2.5, an instant permanent bump.
const DIVE_BOOST := 1.9
## Part of DIVE_BOOST that fades out again after the dive start (0 keeps it all, 1 fades it all).
const DIVE_BOOST_FADE := 0.5
## Time constant (s) of that fade: smooth decay instead of a hard cut.
const DIVE_BOOST_FADE_TIME := 0.35
## After landing a dive, this long (s) before the next one: no slide-jump-dive spam.
const DIVE_COOLDOWN := 0.6
## After a slide ends, this long (s) before a new slide can start.
const SLIDE_COOLDOWN := 0.3
## Hang time: gravity is scaled by APEX_GRAVITY_SCALE while |vel.y| is under APEX_SPEED (m/s) in
## the air, so jumps float a little at the top. Not on wall runs (they set their own sink).
const APEX_SPEED := 2.2
const APEX_GRAVITY_SCALE := 0.6
const DIVE_MAX := 15.0 # horizontal cap at the dive start (AIR_MAX_SPEED is 13.5, CARRY_MAX 18)
const DIVE_UP_GROUND := 4.8
const DIVE_UP_AIR := 2.0
const DIVE_MIN_SPEED := 6.0
const ROLL_TIME := 0.55
const THROW_ANIM_TIME := 0.42 # s, the body's knife-throw flick (#25); the viewmodel uses its own
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
var _dive_cd := 0.0 # DIVE_COOLDOWN left
var _slide_cd := 0.0 # SLIDE_COOLDOWN left
var _dive_fade_left := 0.0 # m/s of the dive boost still to fade out
var _roll_t := 0.0
var _throw_t := 0.0
var _roll_dir := Vector3.FORWARD
var _carry_t := 0.0 # seconds of surf-speed retention left (local sim only)
var _was_surfing := false
var _fall_vy := 0.0 # fastest fall of the current air time (negative), for the landing camera dip
var _was_fall := false # last physics tick was airborne (landing edge, speed_fx only)
var _land_cam_pitch := 0.0 # rad: landing dip on top of camera.move_pitch, eases back to 0
## How much of that dip is currently sitting in camera.move_pitch. Taken out again at the start of the
## next _tick_move_fx, so the dip is a transient channel and never feeds back into the pitch decay.
var _land_dip_applied := 0.0
## This tick's movement keys, taken once. Movement reads these instead of the keyboard, which is what
## lets a bot (BotBrain fills them from its own intent) run the exact same slide, wallrun and dive code
## as a human. Set in _physics_process for a human, in BotBrain.physics_tick for a bot.
var _in_sprint := false
var _in_crouch := false
var _in_crouch_down := false # just pressed this tick
var _strip_cd: Dictionary = {} # strip name -> seconds until this pawn can take it again
var _strip_prev := Vector3.INF
var _whoosh: AudioStreamPlayer
var _los_sfx: AudioStreamPlayer # LOS only: the hands leaving and the body snapping back
var _wind: AudioStreamPlayer # speed FX wind loop (local only); volume/pitch follow the speed
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
var _air_steer_locked := false # #152: no air steering from a wall jump until the floor or the next wallrun
var _walljumps_seen := -1
var _dive_seen_t := -100.0
var _roll_seen_t := -100.0
const STYLE_KEEP := 1.5
const STYLE_RAMP_REACH := 1.0 # m from the body centre (capsule radius ~0.45, plus slack)
const STYLE_TELEPORT_M := 3.0 # one tick moving further than this is a teleport (snapshots move < 1 m)
## Server-side check on the position a client claims (#B1). A client owns its own pawn, so it also
## tells us where it is — and a modified client could say "I am across the map" and shoot from there.
## A claim is only accepted if the pawn could have got there since the last accepted one at the
## fastest speed the game allows: CARRY_MAX sideways, a hard fall plus a dive vertically.
const NET_CLAIM_H_CAP := CARRY_MAX * 1.4 # m/s: surf exit boost and dive stay under this
const NET_CLAIM_V_CAP := 45.0 # m/s: free fall with a dive
const NET_CLAIM_SLACK := 0.6 # m: a step up, a landing, one late snapshot
const NET_CLAIM_MIN_DT := 0.05 # s: never judge against a window smaller than this
const NET_CORRECTION_MS := 250 # ms between corrections: one is enough, we do not spam
## Remote human pawns on a client glide toward the last received pose instead of snapping to it.
## Time constant of that exponential smoothing; matches LagComp.INTERP_MS so lag compensation stays honest.
const NET_SMOOTH_S := 0.05
var _net_target := Vector3.ZERO # last pose received through $Sync (client side, remote humans only)
var _net_has := false # _net_target holds a real pose
var _net_pos_ms := 0 # server: when we last accepted a position claim (#B1)
var _corr_ms := 0 # server: when we last sent a correction (rate limit)

## Replicated stand-in for `position` ($Sync, see _enter_tree). The owner reads its real position;
## a receiver stores it as a target (_smooth_remote) so lost or jittery snapshots do not stutter.
## The server applies it raw: hit tests and the lag-comp history must use the true pose.
var net_pos: Vector3:
	get:
		return position
	set(v):
		_receive_net_pos(v)


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
## $Sync sends net_pos/rotation/Head:rotation as ALWAYS (unreliable, 30 Hz): a lost pose is simply
## replaced by the next one. ON_CHANGE would make them reliable, and on a lossy link one lost packet
## then stalls every later pose and reliable RPC on the channel (head-of-line blocking, high-ping desync).
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
	_attach_arms()
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
		# Its own node: the carry whoosh belongs to Movement, with its own pitch.
		_los_sfx = AudioStreamPlayer.new()
		_los_sfx.stream = WHOOSH
		_los_sfx.bus = "SFX"
		_los_sfx.volume_db = -2.0
		add_child(_los_sfx)
		_wind = AudioStreamPlayer.new()
		_wind.stream = looped_wind()
		_wind.bus = "SFX"
		_wind.volume_db = WIND_VOL_DB_MIN
		add_child(_wind)
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
	if Game.is_gun_game(): # #148: only the ladder step's gun, for humans and bots
		ids.append(GunGame.weapon_at(GunGame.level_of(Game, peer_id)))
		return ids
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
	if Game.is_gun_game():
		return 0 # #148: guns and the knife only
	if loadout.is_empty():
		return GRENADE_MAX
	var g: Dictionary = loadout.get("grenades", {})
	return clampi(int(g.get("frag", 0)), 0, PlayerClasses.MAX_GRENADES)


func knife_max() -> int:
	if Game.is_gun_game():
		return 0
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
	if weapon and Game.is_gun_game():
		apply_loadout() # #148: the bot's ladder step, not its fixed gun
	elif weapon:
		weapon.equip_loadout(loadout_index)


## Local: hide body, capture mouse. Remote/bot: show mesh, nametag, world gun.
func _configure_control() -> void:
	_apply_team_visual()
	if weapon:
		weapon.refit_view() # third-person guns sit closer to the body (B1)
	if is_local():
		body_mesh.visible = false
		weapon.visible = true
		if _arms_enabled() and camera.get_node_or_null("ViewHands") == null:
			var crystal := body_mesh.get_node_or_null("Crystal") as CrystalBody
			CrystalHands.attach_view(camera, weapon, crystal.glow if crystal else _body_mat) # #164: first-person crystal hands
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
	if Game.chat_open or Game.pause_open or Game.killcam_active or Game.rc_view or Game.los_view:
		return # LOS look is the hands' camera; do not eat the mouse event or they never see it
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
	if event.is_action_pressed("grenade") and not is_dead and not Game.play_locked() and not Game.rc_view and not Game.los_view:
		_try_throw_grenade()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("throw_knife") and not is_dead and not Game.play_locked() and not Game.rc_view and not Game.los_view:
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


## #164: the crystal body is visuals only; a dedicated server never builds it.
func _arms_enabled() -> bool:
	return not Game.is_dedicated and body_mesh != null and weapon != null


## #164: B1 crystal body with floating hands that hold the gun (CrystalBody).
func _attach_arms() -> void:
	if _arms_enabled():
		CrystalBody.attach(body_mesh, weapon)


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
	var crystal := body_mesh.get_node_or_null("Crystal") as CrystalBody if body_mesh else null
	if crystal:
		crystal.repaint(col)


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
## `headshot_mult` comes from the gun's WeaponDef — never repeat the numbers here.
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
	# Armour first, then HP (#144). One shield plate absorbs 40 damage.
	var absorbed := mini(roundi(armour), dmg)
	if absorbed > 0:
		dmg -= absorbed
		set_armour(armour - float(absorbed))
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
	# #150: bots turn toward the pawn that hit them. A low HP hit also breaks the trade.
	var attacker := Game.player_for_peer(killer_peer_id)
	if dmg > 0 and not killed and is_bot and _bot_brain != null and attacker != null and attacker != self:
		_bot_brain.note_threat(attacker)
	if dmg <= 0:
		source_pos = Vector3.INF
	elif not source_pos.is_finite():
		if attacker and attacker != self:
			source_pos = attacker.global_position
	if Game.is_networked():
		Game.broadcast_hurt.rpc(peer_id, new_hp, killed, source_pos, roundi(armour))
	else:
		apply_hurt_state(new_hp, killed, source_pos, roundi(armour))
	return {"killed": killed, "headshot": headshot, "damage": dmg}


## True when the capsule hit lands on the drawn head, including while crouched.
func _point_hits_head(point: Vector3) -> bool:
	var center := global_position + Vector3(0.0, lerpf(HEAD_STAND_Y, HEAD_CROUCH_Y, crouch), 0.0)
	var mark := body_mesh.get_node_or_null("HeadHit") if body_mesh else null
	if mark is Node3D:
		center = (mark as Node3D).global_position
	return point.distance_to(center) <= HEAD_HIT_R


## `from_pos`: damage source for the HUD direction indicator (Vector3.INF = unknown).
func apply_hurt_state(new_hp: float, killed: bool, from_pos: Vector3 = Vector3.INF, armour_now := -1) -> void:
	hp = new_hp
	if armour_now >= 0:
		armour = float(armour_now)
		armour_changed.emit(armour)
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
	# LOS ends the same way: camera back on the body, no bash from a corpse.
	if is_local() and Game.rc_view:
		RcXd.release_view()
	var los_id := peer_id if peer_id != 0 else _owner_peer()
	if Game._is_match_authority():
		RcXd.abort_for(peer_id)
		LosHands.abort_for(los_id)
	elif is_local():
		LosHands.abort_for(los_id)
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
	# Armour does not survive a death (#144).
	if armour != 0.0:
		set_armour(0.0)
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
	return 1.0 + minf(_obs_speed / WALK_SPEED, 1.0) * SPREAD_WALK_K * 0.5


## 1.0 is standing still. Walk, sprint, then slide stack on top of the gun's own spread.
func spread_multiplier() -> float:
	# Still is the accurate state. Slide is wider than sprint, which is wider than walking.
	if is_sliding():
		return SPREAD_SLIDE
	if is_sprinting:
		return SPREAD_SPRINT
	var move := minf(Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 1.0)
	return 1.0 + move * SPREAD_WALK_K


## Server simulates bots. Remote humans/bots on a client only apply visuals + footsteps.
func _physics_process(delta: float) -> void:
	_spawn_protect = maxf(_spawn_protect - delta, 0.0)
	if Game._is_match_authority():
		_tick_style_track(delta)
		_check_kill_y()
	if is_bot:
		if Game.is_networked() and not multiplayer.is_server():
			_tick_remote_anim(delta)
			_apply_remote_visual()
			_tick_feet(delta)
			return
		if _bot_brain:
			_bot_brain.physics_tick(delta)
		_tick_feet(delta)
		return
	if not is_local():
		_smooth_remote(delta)
		_tick_remote_anim(delta)
		_apply_remote_visual()
		_tick_feet(delta)
		return
	## Every menu or lock that takes the keys away from the pawn: chat, the pause menu, a round freeze
	## or killcam, the RC view, LOS. The pause menu was missing here, so the local pawn kept walking,
	## sprinting and jumping behind the menu while only look and fire were blocked.
	## LOS locks the stick but does not zero the velocity: the body keeps the line it had.
	var input_locked := Game.chat_open or Game.pause_open or Game.play_locked() or Game.rc_view or Game.los_view
	# The movement keys, once per tick. Movement itself never touches Input any more (see _in_sprint).
	_in_sprint = (not input_locked) and Input.is_action_pressed("sprint")
	_in_crouch = (not input_locked) and Input.is_action_pressed("crouch")
	_in_crouch_down = (not input_locked) and Input.is_action_just_pressed("crouch")
	_carry_t = maxf(_carry_t - delta, 0.0)
	_kb_t = maxf(_kb_t - delta, 0.0)
	_tick_strip_cd(delta)
	if Game.rc_view:
		_sliding = false
		velocity.x = 0.0
		velocity.z = 0.0
	var on_floor := is_on_floor()
	_try_start_slide(on_floor, input_locked)
	_try_air_dive(on_floor, input_locked)
	_update_stance(delta, on_floor)

	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if (not is_dead) and (not input_locked) and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	var jumped := false
	if not on_floor:
		velocity.y += float(get_gravity().y) * delta * Movement.gravity_scale(self)
		_sliding = false
		if (_wallrunning or _wall_off_t <= WALLRUN_COYOTE) and (not is_dead) and (not input_locked) and _jump_buffer > 0.0:
			_wall_jump()
			_jump_buffer = 0.0
	elif (not is_dead) and (not input_locked) and _jump_buffer > 0.0 and _sliding and _dive_cd <= 0.0:
		_sliding = false
		_start_dive(true) # sprint + crouch (slide), then jump: dive
		jumped = true
		_jump_buffer = 0.0
	elif (not is_dead) and (not input_locked) and _jump_buffer > 0.0:
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
	if not is_dead and not input_locked:
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
	elif on_floor and (not is_dead) and (not input_locked) and crouch < 0.2 and Input.is_action_pressed("sprint") and wish.length_squared() > 0.04:
		wish_speed = SPRINT_SPEED
		is_sprinting = true
	elif crouch > 0.5:
		wish_speed = CROUCH_SPEED
	if not _sliding:
		wish_speed *= gun_speed_mult()
	# LOS: wish is the speed the body already has, so friction does not park it.
	# Below COAST_MIN it stands. No new jump, slide or dive (input_locked covers those).
	if los_coast:
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		var spd := hv.length()
		if spd >= LosHands.COAST_MIN:
			wish = hv / spd
			wish_speed = spd
		else:
			wish = Vector3.ZERO
			wish_speed = 0.0

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if jumped or not on_floor:
		# The jump tick is already air: no ground friction, so sprint speed carries into the jump.
		horiz = _air_accelerate(horiz, wish, WALK_SPEED * minf(wish.length(), 1.0), delta)
		if not _air_steer_locked:
			horiz = Movement.air_steer(horiz, wish, delta)
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
	Movement.tick_boosts(self, delta)
	_tick_wallrun(delta, input_vec, input_locked)
	_tick_dive_roll(delta)
	_tick_move_fx(delta)
	_tick_speed_fx(delta)
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
## `stance` (optional, newer servers): [crouch, move_fx], so remote bots crouch, dive and wall-run visibly.
func apply_network_pose(pos: Vector3, yaw: float, pitch: float, stance: Array = []) -> void:
	global_position = pos
	rotation.y = yaw
	_yaw = yaw
	_pitch = pitch
	if head:
		head.rotation.x = pitch
	velocity = Vector3.ZERO
	if stance.size() >= 2:
		crouch = clampf(float(stance[0]), 0.0, 1.0)
		var was := move_fx
		move_fx = int(stance[1])
		_apply_stance()
		# A remote pawn never runs Movement.tick_dive_roll, so _roll_t stays 0 and the roll was
		# invisible on everyone else's screen and in the killcam (#236). The synced move_fx is the
		# signal: the frame it turns MOVE_ROLL, run the local timer that drives the body's flip.
		if move_fx == MOVE_ROLL and was != MOVE_ROLL:
			_roll_t = ROLL_TIME
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


## See net_pos. First pose, the server, or a jump past STYLE_TELEPORT_M (respawn) snaps.
## On the server a claim is checked first: the client only gets to say where it is (#B1).
func _receive_net_pos(v: Vector3) -> void:
	if multiplayer.is_server() and not is_bot:
		_accept_claim(v)
		return
	var smooth := is_inside_tree() and _net_has and not multiplayer.is_server()
	_net_target = v
	_net_has = true
	if not smooth or v.distance_to(position) > STYLE_TELEPORT_M:
		position = v


## #B1 server authority over position. Accept a claim only if the pawn could have reached it since the
## last accepted one; otherwise keep our own copy and send a correction (rate limited). Without this a
## modified client could teleport anywhere and shoot from there — and origin_plausible would agree,
## because it compares the shot against the position that same client just claimed.
func _accept_claim(v: Vector3) -> void:
	var now := Time.get_ticks_msec()
	var dt := maxf(float(now - _net_pos_ms) / 1000.0, NET_CLAIM_MIN_DT)
	if is_dead or _claim_reachable(v, dt):
		position = v
		_net_pos_ms = now
		return
	# Refused. Reset the window as well, so the budget cannot pile up and turn into a slow teleport.
	_net_pos_ms = now
	if now - _corr_ms >= NET_CORRECTION_MS and Game.is_networked() and peer_id in multiplayer.get_peers():
		_corr_ms = now
		Game.correct_position.rpc_id(peer_id, position)


## Could a pawn have gone from where we have it to `v` in `dt` seconds?
func _claim_reachable(v: Vector3, dt: float) -> bool:
	var d := v - position
	var h := Vector2(d.x, d.z).length()
	return h <= NET_CLAIM_H_CAP * dt + NET_CLAIM_SLACK and absf(d.y) <= NET_CLAIM_V_CAP * dt + NET_CLAIM_SLACK


## The server refused our claim: take its copy. Called by Game.correct_position.
func apply_position_correction(v: Vector3) -> void:
	position = v
	_net_target = v
	_net_has = true


## LOS: the hands landed a bash and the body snaps to them. Both the server's copy and the owner's
## move here, so the claim check does not read the jump as a teleport and pull the body back.
## Velocity is dropped: the snap is a cut, not a carry. INF-safe (the caller checks).
func apply_snap(v: Vector3) -> void:
	global_position = v
	_net_target = v
	_net_has = true
	_net_pos_ms = Time.get_ticks_msec()
	velocity = Vector3.ZERO
	_style_last_pos = Vector3.INF # a teleport, so it is never counted as a fall


## LOS hand sounds, local machine only: leaving the body (pitch > 1) and snapping back (< 1).
func play_los_sfx(pitch: float) -> void:
	if _los_sfx == null:
		return
	_los_sfx.pitch_scale = pitch
	_los_sfx.play()


## Client-side glide of a remote human toward _net_target (frame-rate independent).
## A local teleport of the pawn (e.g. a respawn RPC) re-bases the target instead of being pulled back.
func _smooth_remote(delta: float) -> void:
	if not _net_has or multiplayer.is_server():
		return
	if position.distance_to(_net_target) > STYLE_TELEPORT_M:
		_net_target = position
		return
	position = _net_target + (position - _net_target) * exp(-delta / NET_SMOOTH_S)


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
	var want := _sliding or _diving or _roll_t > 0.0 or ((not is_dead) and _in_crouch)
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
	pose_body(body_mesh, crouch, move_fx, roll_flip(), throw_amt(), reload_amt())


## Schildplaat (#144): armour never stacks above the plate's value, and it is gone when you die.
func set_armour(v: float) -> void:
	armour = clampf(v, 0.0, Pickups.ARMOUR)
	armour_changed.emit(armour)


## A pickup did something to this pawn: a short HUD flash in its colour plus a chime.
func play_pickup_flash(t: StringName) -> void:
	if not is_local():
		return
	var info := Pickups.type_info(t)
	if pickup_sfx and pickup_sfx.stream:
		pickup_sfx.pitch_scale = float(info["pitch"])
		pickup_sfx.play()
	var h := get_tree().get_first_node_in_group("hud") as Hud
	if h == null or not h.has_method("flash_pickup"):
		return
	# The popup says what happened, not which type it was (#246 review).
	var text := String(info["label"])
	match t:
		&"knives":
			text = "MESSEN +%d" % Pickups.KNIVES
		&"shield":
			text = "SCHILD"
		&"heal":
			text = "+%d HP" % roundi(Pickups.HEAL)
	h.flash_pickup(text, info["color"])
	if t == &"knives" and h.has_method("blink_knives"):
		h.blink_knives()


## Herstelkern / Schildplaat on a remote pawn (#144): HP and armour without any hurt feedback.
func apply_vitals(hp_now: float, armour_now: float) -> void:
	hp = hp_now
	armour = clampf(armour_now, 0.0, Pickups.ARMOUR)
	if is_local():
		health_changed.emit(hp, MAX_HP)
		armour_changed.emit(armour)


## Herstelkern (#144): HP went up without damage, so only the HUD needs telling.
func apply_heal_visual(hp_now: float) -> void:
	apply_vitals(hp_now, armour)


## 0..1 through the current reload, 0 when the weapon is not reloading (#164).
func reload_amt() -> float:
	return weapon.reload_anim() if weapon else 0.0


## A knife leaves the hand: the body does the overhand flick too, so other players (and the killcam)
## see a throw instead of a standing figure (#25). Local view: Weapon.play_throw().
func play_throw_anim() -> void:
	_throw_t = THROW_ANIM_TIME


## 0..1 through the throw: wind up, then snap forward. Visual only.
func throw_amt() -> float:
	if _throw_t <= 0.0:
		return 0.0
	var t := 1.0 - _throw_t / THROW_ANIM_TIME
	if t < 0.45:
		return smoothstep(0.0, 0.45, t) # behind the shoulder
	return smoothstep(0.45, 1.0, t) # follow through


## The landing roll as a rotation for the body, the same forward flip the local camera does (#205).
## 0 outside a roll, so a body that is not tumbling reads as flat.
func roll_flip() -> float:
	if _roll_t <= 0.0:
		return 0.0
	var pr := 1.0 - _roll_t / ROLL_TIME
	return -TAU * ease(pr, -1.8)


## Puts the head marker (the hit target) on the stance's head height and hands the synced state to
## the crystal body (CrystalBody/BodyPose), which poses itself every frame. Static so the killcam
## ghosts (a copy of BodyMesh) use it too; they only know `crouch`.
static func pose_body(body: Node3D, crouch_amt: float, fx := MOVE_NONE, flip := 0.0, throw_amt := 0.0, reload := 0.0) -> void:
	if body == null:
		return
	var head_y := lerpf(HEAD_STAND_Y, HEAD_CROUCH_Y, crouch_amt)
	var hit := body.get_node_or_null("HeadHit") as Node3D
	if hit:
		hit.position.y = head_y
	var crystal := CrystalBody.ensure(body)
	if crystal:
		crystal.crouch = crouch_amt
		crystal.head_y = head_y
		crystal.move_fx = fx
		crystal.flip = flip
		crystal.throw_amt = throw_amt
		crystal.reload_amt = reload


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


## Hip FOV while running. Speed FX on: the extra FOV scales with horizontal speed from sprint on
## (speed_fov_extra), so a surf or a dive widens the view and walking does not. Speed FX off: the old
## plain sprint flag plus the carry stack. ADS clears it either way; Game.fov stays the hip base.
func _apply_carry_fov() -> void:
	if weapon == null or camera == null:
		return
	if weapon.is_ads():
		camera.extra_fov = 0.0
		return
	if Game.speed_fx:
		camera.extra_fov = speed_fov_extra(_hspeed())
		return
	var extra := SPRINT_FOV if is_sprinting else 0.0
	if _carry_t > 0.0:
		extra += lerpf(CARRY_FOV_MIN, CARRY_FOV_MAX, clampf(_hspeed() / CARRY_MAX, 0.0, 1.0))
	camera.extra_fov = minf(extra, FOV_EXTRA_CAP)


## Horizontal speed the FOV kick, the wind and the speed lines all scale with.
func _hspeed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Speed FX: extra hip FOV for a horizontal speed. 0 below sprint, SPEED_FOV_AT_SPRINT at sprint
## itself, SPEED_FOV_MAX at CARRY_MAX. Pure, so the headless check can call it without a pawn.
## SPEED_FOV_EPS keeps a real sprint at the kick: the velocity vector is float32, so 11.4 m/s
## measures a hair under SPRINT_SPEED and an exact compare would leave sprinting without the kick.
static func speed_fov_extra(hspeed: float) -> float:
	if hspeed < SPEED_FOV_REF - SPEED_FOV_EPS:
		return 0.0
	var t := clampf((hspeed - SPEED_FOV_REF) / (SPEED_FOV_FULL - SPEED_FOV_REF), 0.0, 1.0)
	return minf(lerpf(SPEED_FOV_AT_SPRINT, SPEED_FOV_MAX, t), FOV_EXTRA_CAP)


## Speed FX: 0..1 speed-line intensity for a horizontal speed.
static func speed_lines_intensity(hspeed: float) -> float:
	return clampf((hspeed - SPEED_LINES_START) / (SPEED_LINES_FULL - SPEED_LINES_START), 0.0, 1.0)


## Speed FX: 0..1 wind level for a horizontal speed.
static func speed_wind_level(hspeed: float) -> float:
	return clampf((hspeed - WIND_START) / (WIND_FULL - WIND_START), 0.0, 1.0)


## Speed FX: how far the camera dips for a landing at `fall_speed` m/s (positive, rad, negative =
## looking down). 0 below LAND_CAM_MIN_SPEED, capped at LAND_CAM_DIP_MAX. Pure.
static func speed_land_dip(fall_speed: float) -> float:
	if fall_speed < LAND_CAM_MIN_SPEED:
		return 0.0
	return -minf((fall_speed - LAND_CAM_MIN_SPEED) * LAND_CAM_DIP_PER_MS, LAND_CAM_DIP_MAX)


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
	# #B2: a claim only counts when the server can back it up itself. A client owns its pawn, so a
	# modified client would otherwise farm WALLRUN / DIVE / ROLL / WALLJUMP by lying — and in the style
	# modes those points decide the match. The local pawn and bots are trusted: their state is the sim.
	var trust := is_local() or is_bot
	if move_fx == MOVE_WALLRUN and (trust or _claim_backed(move_fx)):
		if _style_clock - _wallrun_seen_t > Style.MOVE_RECENT:
			var w2w := _style_clock - _walljump_seen_t <= Style.WALL_TO_WALL_WINDOW
			Game.combo_move(peer_id, Combo.WALL_TO_WALL if w2w else Combo.WALLRUN)
		_wallrun_seen_t = _style_clock
	elif move_fx == MOVE_DIVE and (trust or _claim_backed(move_fx)):
		if _style_clock - _dive_seen_t > Style.MOVE_RECENT:
			Game.combo_move(peer_id, Combo.DIVE)
		_dive_seen_t = _style_clock
	elif move_fx == MOVE_ROLL and (trust or _claim_backed(move_fx)):
		if _style_clock - _roll_seen_t > Style.MOVE_RECENT:
			Game.combo_move(peer_id, Combo.ROLL)
		_roll_seen_t = _style_clock
	if walljumps != _walljumps_seen:
		if _walljumps_seen >= 0 and (trust or _claim_backed(MOVE_WALLRUN)):
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


## #B2: how far a wall may be for a claimed wallrun (or wall jump) to be believed. Generous on purpose:
## our own probe must never refuse a trick the player really did.
const CLAIM_WALL_PROBE := 1.2 # m


## Is a claimed movement trick backed by what the server itself can see? The client owns its pawn, so
## move_fx and walljumps arrive as claims, and in the style modes those claims are points. Every test
## here uses something the authority observes for itself: the feet ray (`_style_in_air`), the air time,
## the speed from the snapshots, and a wall probe. Lenient thresholds, because a false "no" costs a
## player a real trick, while a false "yes" only costs what a liar could already claim.
func _claim_backed(fx: int) -> bool:
	match fx:
		MOVE_WALLRUN:
			return _style_in_air and _obs_speed >= Player.WALLRUN_KEEP_SPEED * 0.8 and _wall_beside()
		MOVE_DIVE:
			return _obs_speed >= Player.DIVE_MIN_SPEED * 0.7 or air_time > 0.2
		MOVE_ROLL:
			return _obs_speed >= Player.WALK_SPEED * 0.9
		_:
			return false


## A near-vertical wall within CLAIM_WALL_PROBE of the body centre: eight horizontal rays.
func _wall_beside() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.9, 0.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var to := from + Vector3(cos(a), 0.0, sin(a)) * CLAIM_WALL_PROBE
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and absf(float((hit.normal as Vector3).y)) < Player.WALLRUN_MAX_NY:
			return true
	return false


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
	_dive_cd = 0.0
	_slide_cd = 0.0
	_dive_fade_left = 0.0
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
## Remote pawns never run the local movement tick, so nothing would ever expire their roll and throw
## timers: the body would stay flipped after the synced move_fx has moved on (#236). They are also
## shorter than a snapshot interval, so they run here at full tick rate instead.
func _tick_remote_anim(delta: float) -> void:
	_roll_t = maxf(_roll_t - delta, 0.0)
	_throw_t = maxf(_throw_t - delta, 0.0)


func _tick_move_fx(delta: float) -> void:
	_throw_t = maxf(_throw_t - delta, 0.0)
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
	# Take last tick's landing dip back out before the pitch is re-derived below. Without this the dip
	# fed back into the decay: every tick added it again while the decay only shaved ~10% off, and at
	# 60 Hz the camera dipped to ~2.3x LAND_CAM_DIP_MAX. The cap was never wrong, the channel was.
	camera.move_pitch -= _land_dip_applied
	_land_dip_applied = 0.0
	var roll_target := 0.0
	if _wallrunning:
		var right := transform.basis.x
		# Speed FX leans a touch further into the wall run; the away-from-wall direction is the feel (#80).
		roll_target = -signf(right.dot(_wall_n)) * WALLRUN_TILT * (1.1 if Game.speed_fx else 1.0) * Game.shake_scale()
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


## Speed FX, local player only (Game.speed_fx): the landing camera dip and its easing back to 0.
## Runs right after _tick_move_fx, so the dip is added on top of whatever pitch the dive or the roll
## asked for and never fights it. A dive roll already pitches the camera, so it skips the dip.
## The FOV kick lives in _apply_carry_fov; the speed lines and the wind latch onto this tick too.
func _tick_speed_fx(delta: float) -> void:
	if camera == null:
		return
	if is_dead:
		_fall_vy = 0.0
		_was_fall = false
	elif is_on_floor():
		if _was_fall:
			if Game.speed_fx and not (_roll_t > 0.0 or _diving):
				_land_cam_pitch = minf(_land_cam_pitch, speed_land_dip(-_fall_vy))
			_fall_vy = 0.0
			_was_fall = false
	else:
		_fall_vy = minf(_fall_vy, velocity.y)
		_was_fall = true
	if _land_cam_pitch != 0.0:
		if Game.speed_fx:
			camera.move_pitch += _land_cam_pitch
			_land_dip_applied = _land_cam_pitch
		_land_cam_pitch = lerpf(_land_cam_pitch, 0.0, 1.0 - exp(-LAND_CAM_RECOVER * delta))
		if absf(_land_cam_pitch) < 0.0005:
			_land_cam_pitch = 0.0
	# Speed lines and wind run off the same horizontal speed. Aiming, death, the pause menu and anything
	# else that locks play (chat, round freeze, RC view) silences both, so a fight never reads through a
	# blurred screen and a menu never keeps the wind howling.
	var quiet := is_dead or Game.chat_open or Game.pause_open or Game.play_locked() or Game.rc_view
	if not quiet and weapon != null and weapon.is_ads():
		quiet = true
	var fast := Game.speed_fx and not quiet
	var hspeed := _hspeed()
	_tick_speed_lines(speed_lines_intensity(hspeed) if fast else 0.0, delta)
	_tick_wind(speed_wind_level(hspeed) if fast else 0.0)


## Speed FX: eases the speed-lines overlay toward `target` (0..1). A missing overlay (headless,
## dedicated server) is not an error: there is simply nothing on screen to draw on.
func _tick_speed_lines(target: float, delta: float) -> void:
	if Game.speed_lines == null:
		return
	Game.speed_lines.set_intensity_smooth(target, delta, SPEED_LINES_SMOOTH)


## The wind wav has no loop point of its own (the wav importer's loop params do not survive the
## import here), so the copy the local pawn plays is looped in code: forward, whole file.
static func looped_wind() -> AudioStreamWAV:
	var s := (WIND_LOOP as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	# Frames, not bytes: 16-bit mono is 2 bytes a frame, 8-bit mono 1, and either is doubled in stereo.
	var per_frame := 2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1
	if s.stereo:
		per_frame *= 2
	s.loop_end = s.data.size() / maxi(per_frame, 1)
	return s


## Speed FX wind: one looped player, louder and a little higher with speed, stopped when slow.
## Local pawn only, so it is on the SFX bus (the Effects slider) and never on the Enemies bus.
func _tick_wind(level: float) -> void:
	if _wind == null:
		return
	if level <= 0.0:
		if _wind.playing:
			_wind.stop()
		return
	if not _wind.playing:
		_wind.play()
	_wind.volume_db = lerpf(WIND_VOL_DB_MIN, WIND_VOL_DB_MAX, level)
	_wind.pitch_scale = lerpf(WIND_PITCH_MIN, WIND_PITCH_MAX, level)
