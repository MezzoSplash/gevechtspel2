class_name Weapon
extends Node3D
## Hitscan guns. FX are local; damage is server-side.
## `LOADOUT` is the whole armory (killcam and bots index it). `slots` is what this pawn carries:
## a human's class (primary + secondary, keys 1/2), or the full armory for bots.

const HURT_MASK := 1 | 2 | 4
const LOADOUT: Array[WeaponDef] = [
	preload("res://data/weapons/rifle.tres"),
	preload("res://data/weapons/pistol.tres"),
	preload("res://data/weapons/shotgun.tres"),
	preload("res://data/weapons/sniper.tres"),
	preload("res://data/weapons/smg.tres"), # v0.2.18: append only, killcam frames store the index
	preload("res://data/weapons/revolver.tres"),
]

@export var def: WeaponDef

## Preloaded, not load()ed per pawn: nothing else holds the PackedScenes, so every spawn re-read
## all four GLBs (~0.4 s per pawn). Ten at match start stalled the host long enough for ENet to drop clients.
const MODEL_SCENES := {
	&"rifle": preload("res://assets/weapons/rifle.glb"),
	&"pistol": preload("res://assets/weapons/pistol.glb"),
	&"shotgun": preload("res://assets/weapons/shotgun.glb"),
	&"sniper": preload("res://assets/weapons/sniper.glb"), # slot 4; two body / one head
	&"smg": preload("res://assets/weapons/smg.tscn"), # hand-built low-poly (tools/build_lowpoly_weapons.py)
	&"revolver": preload("res://assets/weapons/revolver.tscn"),
}
## Throwing knife: in hand for the F throw, and the flying/stuck projectile.
const KNIFE_SCENE := preload("res://assets/weapons/knife.tscn")

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
var _click_left := 0.0 # buffered semi-auto click (see _wants_fire)
var _reload_left := 0.0
var _flash_left := 0.0
var _kick_offset := Vector3.ZERO
var _bob_t := 0.0
var _rest_pos: Vector3
var _view_rest: Vector3
var _hud: Hud
var _weapon_state: Dictionary = {}
var _active_index := 0 # index into `slots`
var slots: Array[WeaponDef] = []
var _view_models: Dictionary = {} # StringName → Node3D
var _ads := false
## Held-trigger counter for automatic guns: +1 on every new press (humans) or new burst (bots).
## Only for the SPRAY TRANSFER trick; the server also ends a burst after Style.BURST_GAP.
var burst_seq := 0
var _trigger_held := false
var _melee_left := 0.0 # animation time left
var _melee_cd := 0.0 # local cooldown (the server keeps its own)
var _melee_swing_sfx: AudioStreamPlayer3D
var _melee_hit_sfx: AudioStreamPlayer3D
const CLICK_BUFFER := 0.12
const MELEE_ANIM := 0.36 # seconds: thrust out, hold, pull back
const MELEE_SWING := preload("res://assets/sounds/melee_swing.wav")
const MELEE_HIT := preload("res://assets/sounds/melee_hit.wav")
const ADS_TIME := 0.09 # s to slide the SMG to the centre (fast ADS)
const THROW_ANIM := 0.34 # knife in hand: wind up, release, gun comes back
## Per weapon id: +1 on every fresh magazine (reload done, spawn refill). Sent with each shot so the
## server can tell "one magazine" apart for HOSE and SIX SHOOTER.
var mag_seq: Dictionary = {}
## Time.get_ticks_msec() of the last real switch to the held gun (QUICKDRAW). Spawn/class set: no draw.
var drawn_ms := -100000
var _ads_k := 0.0
var _throw_left := 0.0
var _knife_view: Node3D
var _knife_root := Vector3.ZERO


func _ready() -> void:
	if def == null:
		def = LOADOUT[0]
	_rest_pos = position
	_view_rest = position
	muzzle_flash.visible = false
	muzzle_light.visible = false
	_hide_blockout_meshes()
	_setup_view_models()
	if slots.is_empty():
		slots = LOADOUT.duplicate()
	_equip_def(def, false)
	_melee_swing_sfx = _melee_player(MELEE_SWING, -4.0)
	_melee_hit_sfx = _melee_player(MELEE_HIT, -2.0)
	call_deferred("_hook_hit_fx")


func _melee_player(stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	s.stream = stream
	s.volume_db = db
	s.bus = "SFX"
	s.unit_size = 6.0
	s.max_distance = 40.0
	s.max_polyphony = 2
	add_child(s)
	return s


func _hook_hit_fx() -> void:
	if _is_local() and not Game.hit_confirmed.is_connected(_on_confirmed_hit):
		Game.hit_confirmed.connect(_on_confirmed_hit)


## Weapon switch is allowed during reload and cancels it (sidearm ready immediately).
func _process(delta: float) -> void:
	var owner_player := owner as Player
	var bot_auth := owner_player != null and owner_player.is_bot and (Game.is_offline or multiplayer.is_server())
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	if not _is_local():
		_tick_melee_pose(delta, Vector3.ZERO)
	if not _is_local() and not bot_auth:
		return
	# May go below 0: _fire carries the leftover so the rate does not depend on the frame rate.
	_cooldown = maxf(_cooldown - delta, -1.0)
	_click_left = maxf(_click_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left <= 0.0:
		muzzle_flash.visible = false
		muzzle_light.visible = false
	_update_ads()
	if bot_auth:
		if _reload_left > 0.0:
			_reload_left = maxf(_reload_left - delta, 0.0)
			if _reload_left <= 0.0:
				ammo = def.mag_size
				_new_mag(def.id)
				_save_weapon_state()
		return

	var trigger := Input.is_action_pressed("fire")
	if trigger and not _trigger_held:
		burst_seq += 1
	_trigger_held = trigger
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _owner_alive() and not Game.chat_open and not Game.pause_open and not Game.play_locked():
		if Input.is_action_just_pressed("melee"):
			Game.melee.swing(owner_player)
		elif Input.is_action_just_pressed("switch_weapon"):
			_cycle_weapon()
		elif Input.is_action_just_pressed("weapon_1"):
			_equip(0)
		elif Input.is_action_just_pressed("weapon_2"):
			_equip(1)
		elif Input.is_action_just_pressed("weapon_3"):
			_equip(2)
		elif Input.is_action_just_pressed("weapon_4"):
			_equip(3)
		elif _reload_left > 0.0 or _melee_left > 0.0:
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
			_new_mag(def.id)
			_save_weapon_state()
			rotation.x = 0.0
			_refresh_hud()

	_kick_offset = _kick_offset.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * delta))
	_bob_t += delta * (8.0 + speed_factor * 6.0)
	var bob := Vector3.ZERO
	if speed_factor > 0.08:
		bob.x = sin(_bob_t) * 0.012 * speed_factor
		bob.y = absf(sin(_bob_t * 2.0)) * 0.01 * speed_factor
	_ads_k = move_toward(_ads_k, 1.0 if (_ads and not def.ads_hides_model) else 0.0, delta / ADS_TIME)
	var rest := _view_rest.lerp(_ads_pose(), smoothstep(0.0, 1.0, _ads_k))
	position = rest + _kick_offset + bob * (1.0 - _ads_k * 0.7)
	_tick_melee_pose(delta, _kick_offset + bob)
	_tick_throw_pose(delta)


func melee_ready() -> bool:
	return _melee_cd <= 0.0


## Thrust animation + swing sound. Cancels a reload and blocks firing until the gun is back.
func play_melee() -> void:
	_melee_cd = Melee.COOLDOWN
	_melee_left = MELEE_ANIM
	var p := owner as Player
	if _is_local() or p.is_bot:
		if _reload_left > 0.0:
			if _is_local():
				_cancel_reload()
			else:
				_reload_left = 0.0
			_save_weapon_state()
		_cooldown = maxf(_cooldown, MELEE_ANIM * 0.85)
		rotation = Vector3.ZERO
	if _melee_swing_sfx:
		_melee_swing_sfx.pitch_scale = randf_range(0.93, 1.07)
		_melee_swing_sfx.play()
	if _is_local() and camera:
		camera.add_kick(-1.2, randf_range(-0.6, 0.6), -4.0)


func play_melee_hit() -> void:
	if _melee_hit_sfx:
		_melee_hit_sfx.pitch_scale = randf_range(0.94, 1.06)
		_melee_hit_sfx.play()


func play_hit_feedback(killed: bool, headshot: bool) -> void:
	_play_hit_fx(killed, headshot)


## 0 → 1 fast (stab out), short hold, then ease back to 0.
func _melee_amount() -> float:
	var t := 1.0 - _melee_left / MELEE_ANIM
	if t < 0.3:
		return sin(t / 0.3 * PI * 0.5)
	if t < 0.45:
		return 1.0
	return 1.0 - smoothstep(0.45, 1.0, t)


## Short bash: the gun swings sideways toward the centre and forward, so its side leads.
## Local view and remote pawns alike.
func _tick_melee_pose(delta: float, base: Vector3) -> void:
	if _melee_left <= 0.0:
		return
	_melee_left = maxf(_melee_left - delta, 0.0)
	var k := _melee_amount() if _melee_left > 0.0 else 0.0
	position = _view_rest + base + Vector3(-0.13, 0.05, -0.12) * k
	rotation = Vector3(-0.1, 0.75, 0.4) * k


## Semi-auto (pistol, shotgun, sniper): one shot per click. Holding does nothing more.
## A click just before the gun is ready is kept for CLICK_BUFFER, so fast tapping is not eaten.
func _wants_fire() -> bool:
	if def.automatic:
		return Input.is_action_pressed("fire")
	if Input.is_action_just_pressed("fire"):
		_click_left = CLICK_BUFFER
	if _click_left > 0.0 and _cooldown <= 0.0:
		_click_left = 0.0
		return true
	return false


func _owner_sliding() -> bool:
	var p := owner as Player
	return p != null and p.is_sliding()


func is_ads() -> bool:
	return _ads


## Hold RMB on a gun with `ads_fov`: sniper scope (FOV 38, viewmodel hidden) or SMG iron sights
## (FOV 72, gun slides to the centre, tighter spread). Other guns never ADS.
func _update_ads() -> void:
	var want := (
		_is_local()
		and def != null
		and def.ads_fov > 0.0
		and _throw_left <= 0.0
		and _owner_alive()
		and not Game.chat_open
		and not Game.pause_open
		and not Game.play_locked()
		and not _owner_sliding()
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_pressed("zoom")
	)
	_ads = want
	if camera:
		camera.ads_fov = def.ads_fov if _ads else 0.0
	var scope := _ads and def.ads_hides_model
	var hud := _hud_node()
	if hud:
		hud.set_sniper_ads(scope)
	for id in _view_models:
		var n: Node3D = _view_models[id]
		n.visible = (not scope) and _throw_left <= 0.0 and def != null and id == def.id


## Mouse sensitivity factor while aiming: the sniper scope uses the player's ADS setting,
## iron sights just follow the zoom (72/90) so the feel stays the same.
func ads_sens_mult() -> float:
	if def == null or not _ads:
		return 1.0
	if def.ads_hides_model:
		return Game.ads_sens
	return clampf(def.ads_fov / 90.0, 0.2, 1.0)


func _ads_pose() -> Vector3:
	return Vector3(0.0, -0.092, _view_rest.z - 0.02)


func _cycle_weapon() -> void:
	if not _owner_alive():
		return
	if slots.size() > 1:
		_equip((_active_index + 1) % slots.size())


## Bots: armory index (they carry everything and never switch).
func equip_loadout(index: int) -> void:
	_equip_def(LOADOUT[clampi(index, 0, LOADOUT.size() - 1)], false)


## Slot of the held gun in `slots`.
func active_index() -> int:
	return _active_index


## Armory index of the held gun (killcam frames use it; stable across classes).
func armory_index() -> int:
	return _armory_index(def)


func has_weapon(id: StringName) -> bool:
	for w in slots:
		if w.id == id:
			return true
	return false


## Class change / spawn: carry only these guns and hold the first one. Unknown ids are skipped.
func set_slots(ids: Array) -> void:
	var out: Array[WeaponDef] = []
	for id in ids:
		var w := _def_for_id(StringName(id))
		if w and not out.has(w):
			out.append(w)
	if out.is_empty():
		out = LOADOUT.duplicate()
	slots = out
	_cancel_reload()
	_melee_left = 0.0
	_equip_def(slots[0], false)


## Remote copy of someone else's gun (Game.sync_weapon). No HUD, no ammo bookkeeping that matters.
## Remote copies do not know the class, so this goes by id and ignores `slots`.
func equip_remote(id: StringName) -> void:
	var w := _def_for_id(id)
	if w == null or (def != null and w.id == def.id):
		return
	_equip_def(w, false)
	drawn_ms = Time.get_ticks_msec() # the server's view of a client's real switch (QUICKDRAW)


## Number keys / Q. Out of range (key 3 with two guns) does nothing.
func _equip(index: int, save_current: bool = true) -> void:
	if index < 0 or index >= slots.size():
		return
	_equip_def(slots[index], save_current)


## Switching stores ammo of the old gun and loads the new one. Reload leftover is dropped.
func _equip_def(weapon_def: WeaponDef, save_current: bool = true) -> void:
	if weapon_def == null:
		weapon_def = slots[0] if not slots.is_empty() else LOADOUT[0]
	if save_current and def != null and weapon_def.id == def.id:
		return
	if save_current and def != null:
		_cancel_reload()
		_save_weapon_state()
	_active_index = maxi(slots.find(weapon_def), 0)
	def = weapon_def
	_click_left = 0.0
	var state := _load_weapon_state(def.id)
	ammo = int(state.ammo)
	_reload_left = 0.0
	rotation.x = 0.0
	if def.fire_sound:
		fire_sfx.stream = def.fire_sound
	_apply_view_for_def()
	_refresh_hud()
	drawn_ms = Time.get_ticks_msec() if save_current else -100000
	_ads_k = 0.0
	if save_current and _is_local():
		Game.announce_weapon(owner as Player, def.id)


## Server copy following a client's switch, or the shooter itself: seconds since the held gun was drawn.
func since_draw() -> float:
	return float(Time.get_ticks_msec() - drawn_ms) / 1000.0


func _new_mag(id: StringName) -> void:
	mag_seq[id] = int(mag_seq.get(id, 0)) + 1


func mag_of(id: StringName) -> int:
	return int(mag_seq.get(id, 0))


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


func _armory_index(weapon_def: WeaponDef) -> int:
	if weapon_def == null:
		return 0
	for i in LOADOUT.size():
		if LOADOUT[i].id == weapon_def.id:
			return i
	return 0


func _hide_blockout_meshes() -> void:
	if gun_body:
		gun_body.visible = false
	if barrel:
		barrel.visible = false
	if mag:
		mag.visible = false


func _setup_view_models() -> void:
	for id in MODEL_SCENES:
		var ps := MODEL_SCENES[id] as PackedScene
		if ps == null:
			continue
		var inst: Node3D = ps.instantiate() as Node3D
		inst.name = String(id)
		inst.visible = false
		no_shadows(inst)
		add_child(inst)
		_view_models[id] = inst


static func no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		no_shadows(c)


func _apply_view_for_def() -> void:
	_hide_blockout_meshes()
	for id in _view_models:
		(_view_models[id] as Node3D).visible = false
	if not _view_models.has(def.id):
		return
	var model: Node3D = _view_models[def.id]
	model.visible = true
	var fit := fit_model(model, def.id, _rest_pos)
	position = fit.root
	muzzle.position = fit.muzzle
	_view_rest = position


## Scales and centres a gun GLB for this slot. Returns where the gun root sits under the camera
## ("root") and the muzzle in root space ("muzzle"). The killcam ghosts use the same numbers.
static func fit_model(model: Node3D, id: StringName, rest_pos: Vector3) -> Dictionary:
	# GLBs are modeled along +X; +90 Y puts the muzzle down camera -Z.
	model.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	model.position = Vector3.ZERO
	model.scale = Vector3.ONE
	var root := Vector3(rest_pos.x, rest_pos.y, rest_pos.z + 0.06)
	var length := 0.42
	match id:
		&"pistol":
			root = Vector3(0.20, -0.16, -0.26)
			length = 0.30
		&"shotgun":
			root = Vector3(0.22, -0.18, -0.30)
			length = 0.50
		&"sniper":
			root = Vector3(0.22, -0.17, -0.28)
			length = 0.58
		&"smg":
			root = Vector3(0.21, -0.17, -0.27)
			length = 0.40
		&"revolver":
			root = Vector3(0.19, -0.15, -0.30)
			length = 0.30
		&"knife":
			root = Vector3(0.19, -0.15, -0.30)
			length = 0.25
	var aabb := _aabb_in_parent(model)
	var long := maxf(aabb.size.z, 0.05)
	var s := length / long
	model.scale = Vector3(s, s, s)
	aabb = _aabb_in_parent(model)
	var center := aabb.get_center()
	model.position -= Vector3(center.x, center.y + 0.02, center.z + length * 0.18)
	aabb = _aabb_in_parent(model)
	return {"root": root, "muzzle": Vector3(0.0, aabb.get_center().y, aabb.position.z)}


static func _aabb_in_parent(n: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array = [[n, n.transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh:
				var a := xf * mi.mesh.get_aabb()
				if not has:
					acc = a
					has = true
				else:
					acc = acc.merge(a)
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
			else:
				stack.append([c, xf])
	return acc if has else AABB(Vector3.ZERO, Vector3.ONE)


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
	# Small random pitch so a held trigger does not sound like one looped sample.
	fire_sfx.pitch_scale = randf_range(0.95, 1.05)
	fire_sfx.play()


func bot_try_fire() -> bool:
	if _cooldown > 0.0 or _reload_left > 0.0:
		return false
	if ammo <= 0:
		_start_reload()
		return false
	_fire()
	return true


## Muzzle FX always. Clients ask the server to resolve hits; host/bots fire locally.
func _fire() -> void:
	ammo -= 1
	_save_weapon_state()
	# Carry at most one frame of overshoot, so a held trigger fires at the real rate at any fps.
	var frame := maxf(get_process_delta_time(), get_physics_process_delta_time())
	_cooldown = maxf(_cooldown, -frame) + 1.0 / def.fire_rate
	var kick_z := 0.055 if def.id != &"shotgun" else 0.09
	_kick_offset += Vector3(0.0, 0.0, kick_z)
	_kick_offset.y += randf_range(-0.008, 0.004)
	_flash_left = 0.06 if def.id == &"shotgun" else 0.045
	muzzle_flash.visible = true
	muzzle_light.visible = true
	muzzle_light.light_energy = 5.5 if def.id == &"shotgun" else 4.5
	play_fire_sfx()

	var shooter := owner as Player
	Game.killcam.note_fire(shooter.peer_id if shooter else 0, def.id)
	if shooter == null or not shooter.is_bot:
		var yaw_kick := randf_range(-def.kick_yaw_deg, def.kick_yaw_deg)
		camera.add_kick(def.kick_pitch_deg, yaw_kick, def.kick_fov)
		var hud := _hud_node()
		if hud:
			hud.punch_crosshair(_crosshair_punch())
		_refresh_hud()

	var origin := camera.global_position
	var look_dir := -camera.global_transform.basis.z
	var spread_mult := _spread_multiplier()
	if shooter and shooter.is_bot:
		if def.id == &"shotgun":
			spread_mult *= 1.2
		elif def.id == &"pistol":
			spread_mult *= 1.9
		elif def.id == &"sniper":
			spread_mult *= 1.35
		elif def.id == &"smg":
			spread_mult *= 2.0
		elif def.id == &"revolver":
			spread_mult *= 1.7
		else:
			spread_mult *= 2.4
	# One seed for the tracers here and the hit rays on the server, so they line up.
	var shot_seed := randi() | 1
	var tracer_to := _simulate_pellets_fx(origin, look_dir, spread_mult, shot_seed)
	if Game.is_networked() and multiplayer.is_server() and shooter:
		Game.broadcast_shot_fx(muzzle.global_position, tracer_to, shooter.peer_id)

	# NOSCOPE trick; the sniper scope never changes damage or spread (SMG iron sights do, via spread_mult).
	var scoped := is_ads()
	var burst := burst_seq if def.automatic else 0 # SPRAY TRANSFER only
	var mag_id := mag_of(def.id) # HOSE / SIX SHOOTER only
	if Game.is_networked() and not multiplayer.is_server():
		Game.request_weapon_fire.rpc_id(
			1, origin, look_dir, def.id, muzzle.global_position, spread_mult, shot_seed, scoped, burst, mag_id
		)
	elif shooter:
		var best: Dictionary = Game.fire_weapon_locally(
			shooter, origin, look_dir, def, spread_mult, shot_seed, scoped, burst, mag_id
		)
		if best.get("hit", false) and not shooter.is_bot:
			Game.hit_confirmed.emit(best.killed, best.headshot)
			_play_hit_fx(best.killed, best.headshot)

	if ammo <= 0:
		_start_reload()


## Same rays as Game._resolve_weapon_fire (same seed, spread, and excludes), but only FX.
func _simulate_pellets_fx(origin: Vector3, look_dir: Vector3, spread_mult: float, shot_seed: int) -> Vector3:
	look_dir = look_dir.normalized()
	var spread := def.spread_deg * spread_mult
	var space := camera.get_world_3d().direct_space_state
	var shooter := owner as Player
	var tracer_end := origin + look_dir * def.range_m
	var rng := RandomNumberGenerator.new()
	rng.seed = shot_seed
	for i in def.pellet_count:
		var dir := Game.spread_dir(look_dir, spread, rng)
		var to := origin + dir * def.range_m
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.collision_mask = HURT_MASK
		if shooter:
			query.exclude = Game.shot_exclude(shooter)
		var hit := space.intersect_ray(query)
		var end: Vector3 = to
		if hit:
			end = hit.position
			_spawn_spark(hit.position, hit.normal)
			Game.impacts.add(hit.position, hit.normal, hit.collider)
		_spawn_tracer(muzzle.global_position, end)
		if i == 0:
			tracer_end = end
	return tracer_end


func _on_confirmed_hit(killed: bool, headshot: bool) -> void:
	if Game.is_offline or multiplayer.is_server():
		return
	_play_hit_fx(killed, headshot)


## Headshot tick plays on a kill too, under the kill sting.
func _play_hit_fx(killed: bool, headshot: bool) -> void:
	if headshot and head_sfx.stream:
		head_sfx.play()
	if killed:
		if kill_sfx.stream:
			kill_sfx.play()
		Game.hitstop()
	elif not headshot and hit_sfx.stream:
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
		spread *= def.spread_mult_for(p.spread_multiplier(), is_ads())
	return spread


func _crosshair_punch() -> float:
	var p := owner as Player
	if p and p.is_sprinting:
		return 1.6 if def.move_spread_scale >= 1.0 else 1.2
	if def.id == &"shotgun":
		return 2.2
	if def.id == &"revolver":
		return 1.8
	return 1.0


## Throwing knife (F): the knife shows in the right hand for a quick overhand flick, the gun dips out.
## Local view only; the server spawns the real projectile.
func play_throw() -> void:
	if _knife_view == null:
		_knife_view = Node3D.new() # pivot; fit_model owns the model's own transform
		_knife_view.name = "KnifeView"
		var model := KNIFE_SCENE.instantiate() as Node3D
		no_shadows(model)
		_knife_view.add_child(model)
		get_parent().add_child(_knife_view)
		var fit := fit_model(model, &"knife", _rest_pos)
		_knife_root = fit.root
	if _reload_left > 0.0:
		_cancel_reload()
		_save_weapon_state()
	_throw_left = THROW_ANIM
	_cooldown = maxf(_cooldown, THROW_ANIM * 0.8)
	_tick_throw_pose(0.0)


func is_throwing() -> bool:
	return _throw_left > 0.0


func _tick_throw_pose(delta: float) -> void:
	if _knife_view == null:
		return
	if _throw_left <= 0.0:
		_knife_view.visible = false
		return
	_throw_left = maxf(_throw_left - delta, 0.0)
	var t := 1.0 - _throw_left / THROW_ANIM
	# 0-0.45: raise behind the shoulder; 0.45-0.6: snap forward; then the hand is empty.
	var wind := smoothstep(0.0, 0.45, t)
	var snap := smoothstep(0.45, 0.6, t)
	_knife_view.visible = _throw_left > 0.0 and t < 0.62
	_knife_view.position = _knife_root + Vector3(0.02, 0.08 * wind - 0.02 * snap, 0.10 * wind - 0.30 * snap)
	_knife_view.rotation = Vector3(0.9 * wind - 1.5 * snap, 0.0, -0.25 * wind)
	for id in _view_models:
		(_view_models[id] as Node3D).visible = def != null and id == def.id and _throw_left <= 0.0
	if _throw_left <= 0.0:
		_apply_view_for_def()


func refill() -> void:
	for weapon_def in slots:
		_weapon_state[weapon_def.id] = {
			"ammo": weapon_def.mag_size,
			"reload_left": 0.0,
		}
		_new_mag(weapon_def.id)
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
		var names: PackedStringArray = []
		for w in slots:
			names.append(w.display_name)
		hud.set_weapon_slots(names)
		hud.set_weapon_index(_active_index)
		hud.set_ammo(ammo, def.mag_size)
		hud.set_reloading(_reload_left > 0.0)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var shooter := owner as Player
	Game.killcam.note_tracer(shooter.peer_id if shooter else 0, from, to, def.id)
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
