class_name Killcam
extends Node
## Final killcam (Call of Duty style). Every machine with a screen records what it saw in a short
## rolling buffer: pawn poses at RATE Hz, shots, hits, deaths, grenades. When a round ends, the server
## only names the final kill; each machine replays it from its own buffer through the killer's eyes.
## That keeps the messages tiny, and the replay is exactly what that player saw.
## A dedicated server records and draws nothing: it locks the match, sends "play", then unlocks.
## Lives at /root/Game/Killcam on every peer (Game adds it), so its RPCs resolve everywhere.

signal finished ## the lock is off again: the round-end board comes back

const RATE := 30.0 # snapshots per second
const KEEP := 7.0 # seconds of history
const PRE := 3.5 # the replay starts this long before the kill
const POST := 1.0 # and runs this long after it; the server waits POST before it sends "play"
const SLOW_FROM := 0.3 # slow motion from this long before the kill
const SLOW_TO := 0.25 # until this long after it
const SLOW := 0.35 # playback speed in the slow part
const GRACE := 0.3 # server: room for latency before it unlocks
const TRACER_LIFE := 0.055
const FLASH_LIFE := 0.05
const BAR_H := 64.0
const SNAP_JUMP := 4.0 # metres between snapshots that count as a teleport (respawn): no blending

var _clock := 0.0 # recording time; pauses with the tree like the game does
var _snap_t := 0.0
var _frames: Array = [] # [t, {peer_id: [pos, yaw, pitch, crouch, weapon_index, alive]}, grenade positions]
var _events: Array = [] # [t, kind, a, b, c, d]
var _meta: Dictionary = {} # peer_id -> [name, team]
var _clips: Dictionary = {} # victim peer_id -> their last death, kept for rounds that end on the clock
var _pending_clips: Array = [] # [victim peer_id, death time]

var _playing := false
var _clip: Dictionary = {}
var _pt := 0.0 # playback position on the recording timeline
var _t_kill := 0.0
var _t_end := 0.0
var _frame_i := 0
var _ev_i := 0
var _ghosts: Dictionary = {} # peer_id -> ghost parts (see _make_ghost)
var _nades: Array[MeshInstance3D] = []
var _hidden: Array[Node3D] = []
var _hud: CanvasItem
var _hud_was_visible := false
var _prev_cam: Camera3D
var _cam: Camera3D
var _cam_kick := 0.0
var _rest := Vector3(0.24, -0.18, -0.42)
var _overlay: CanvasLayer
var _draw: Control
var _hit_t := 0.0
var _hit_kill := false
var _hit_head := false
var _sfx_hit: AudioStreamPlayer
var _sfx_head: AudioStreamPlayer
var _sfx_kill: AudioStreamPlayer


func _ready() -> void:
	_sfx_hit = _ui_sound("res://assets/sounds/hit.wav", -6.0)
	_sfx_head = _ui_sound("res://assets/sounds/headshot.wav", -5.0)
	_sfx_kill = _ui_sound("res://assets/sounds/kill.wav", -3.0)


func _ui_sound(path: String, db: float) -> AudioStreamPlayer:
	var s := AudioStreamPlayer.new()
	s.stream = load(path)
	s.volume_db = db
	s.bus = "SFX"
	add_child(s)
	return s


## Length of the replay itself (real seconds), the same on every machine.
static func play_length() -> float:
	return (PRE - SLOW_FROM) + (SLOW_FROM + SLOW_TO) / SLOW + (POST - SLOW_TO)


## Server: from the final kill to the end of the replay, including the wait for POST.
static func total_time() -> float:
	return POST + play_length() + GRACE


func is_playing() -> bool:
	return _playing


# --- Network: the server decides, every machine (and the offline game) runs the same code ---

## Server / offline: lock (or unlock) the match everywhere. Unlocking also ends a replay that still runs.
func set_lock(on: bool) -> void:
	if Game.is_networked():
		if multiplayer.is_server():
			sync_lock.rpc(on)
	else:
		_apply_lock(on)


## Late joiner during a killcam: lock only. They have nothing recorded to replay.
func send_lock_to(peer_id: int) -> void:
	if Game.is_networked() and multiplayer.is_server():
		sync_lock.rpc_id(peer_id, true)


@rpc("authority", "call_local", "reliable")
func sync_lock(on: bool) -> void:
	_apply_lock(on)


func _apply_lock(on: bool) -> void:
	Game.killcam_active = on
	if on:
		Game.clear_radar()
		return
	if _playing:
		_end_playback()
	finished.emit()


## Server / offline: everyone replays this kill (Game.final_kill) from their own buffer.
func play_final(info: Dictionary) -> void:
	if Game.is_networked():
		if multiplayer.is_server():
			sync_play.rpc(info)
	else:
		_start_playback(info)


@rpc("authority", "call_local", "reliable")
func sync_play(info: Dictionary) -> void:
	_start_playback(info)


## Leave to menu: drop the replay and everything recorded.
func reset() -> void:
	if _playing:
		_end_playback()
	_frames.clear()
	_events.clear()
	_meta.clear()
	_clips.clear()
	_pending_clips.clear()
	_clock = 0.0
	_snap_t = 0.0


# --- Recording ---

func _should_record() -> bool:
	return not Game.is_dedicated and not Game.in_lobby and not _playing


func note_fire(peer_id: int, weapon_id: StringName) -> void:
	_note("fire", peer_id, weapon_id)


func note_tracer(peer_id: int, from: Vector3, to: Vector3, weapon_id: StringName) -> void:
	_note("tracer", peer_id, from, to, weapon_id)


func note_hurt(peer_id: int) -> void:
	_note("hurt", peer_id)


func note_death(peer_id: int) -> void:
	if _should_record():
		_pending_clips.append([peer_id, _clock])
	_note("death", peer_id)


func note_boom(pos: Vector3) -> void:
	_note("boom", pos)


func _note(kind: String, a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null) -> void:
	if not _should_record():
		return
	_events.append([_clock, kind, a, b, c, d])


func _process(delta: float) -> void:
	if _playing:
		_tick_playback(delta)
		return
	if not _should_record():
		return
	_clock += delta
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = maxf(_snap_t + 1.0 / RATE, 0.0)
		_snapshot()
	var cut := _clock - KEEP
	while not _frames.is_empty() and float(_frames[0][0]) < cut:
		_frames.pop_front()
	while not _events.is_empty() and float(_events[0][0]) < cut:
		_events.pop_front()
	while not _pending_clips.is_empty() and _clock >= float(_pending_clips[0][1]) + POST + 0.05:
		var entry: Array = _pending_clips.pop_front()
		_clips[int(entry[0])] = _slice(float(entry[1]))


func _snapshot() -> void:
	var pawns := {}
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_queued_for_deletion() or p.head == null:
			continue
		var wpn := p.weapon.active_index() if p.weapon else 0
		pawns[p.peer_id] = [p.global_position, p.rotation.y, p.head.rotation.x, p.crouch, wpn, not p.is_dead]
		_meta[p.peer_id] = [p.display_name, p.team_id]
	if pawns.is_empty():
		return
	var nades := PackedVector3Array()
	for g in get_tree().get_nodes_in_group("grenade"):
		var n3 := g as Node3D
		if n3 and n3.is_inside_tree() and not n3.is_queued_for_deletion():
			nades.append(n3.global_position)
	_frames.append([_clock, pawns, nades])


## PRE before to POST after the kill, plus a little margin for blending.
func _slice(t_kill: float) -> Dictionary:
	var t0 := t_kill - PRE - 0.2
	var t1 := t_kill + POST + 0.2
	var frames: Array = []
	for f in _frames:
		if float(f[0]) >= t0 and float(f[0]) <= t1:
			frames.append(f)
	var events: Array = []
	for e in _events:
		if float(e[0]) >= t_kill - PRE and float(e[0]) <= t1:
			events.append(e)
	return {"t_kill": t_kill, "frames": frames, "events": events, "meta": _meta.duplicate(true)}


## The victim's latest death still in the buffer, else the clip kept from their last death.
func _find_clip(victim: int) -> Dictionary:
	for i in range(_events.size() - 1, -1, -1):
		var e: Array = _events[i]
		if e[1] == "death" and int(e[2]) == victim:
			return _slice(float(e[0]))
	return _clips.get(victim, {})


func _clip_has(clip: Dictionary, peer_id: int) -> bool:
	for f in clip.frames:
		if (f[1] as Dictionary).has(peer_id):
			return true
	return false


# --- Playback ---

func _start_playback(info: Dictionary) -> void:
	if Game.is_dedicated or _playing or typeof(info) != TYPE_DICTIONARY:
		return
	var killer := int(info.get("k", 0))
	var clip := _find_clip(int(info.get("v", 0)))
	# Joined too late, or the kill fell out of the buffer: no replay. The lock still holds.
	if clip.is_empty() or (clip.frames as Array).size() < 2 or not _clip_has(clip, killer):
		return
	_clip = clip
	_clip["info"] = info
	var frames: Array = clip.frames
	_t_kill = float(clip.t_kill)
	_pt = maxf(_t_kill - PRE, float(frames[0][0]))
	_t_end = minf(_t_kill + POST, float(frames[frames.size() - 1][0]))
	_frame_i = 0
	_ev_i = 0
	var events: Array = clip.events
	while _ev_i < events.size() and float(events[_ev_i][0]) < _pt:
		_ev_i += 1 # recorded before our first snapshot (late join): nothing to attach them to
	_cam_kick = 0.0
	_hit_t = 0.0
	_build_ghosts(killer)
	if _cam == null:
		_free_ghosts()
		_clip = {}
		return
	_hide_live_world()
	_build_overlay(info)
	_prev_cam = get_viewport().get_camera_3d()
	_cam.current = true
	_playing = true
	_apply_frames(_pt)


func _speed_at(t: float) -> float:
	return SLOW if t >= _t_kill - SLOW_FROM and t < _t_kill + SLOW_TO else 1.0


func _tick_playback(delta: float) -> void:
	delta = minf(delta, 0.1)
	var speed := _speed_at(_pt)
	_pt += delta * speed
	_apply_frames(_pt)
	_run_events(_pt, speed)
	_hide_new_pawns()
	_hit_t = maxf(_hit_t - delta, 0.0)
	_cam_kick = lerpf(_cam_kick, 0.0, 1.0 - exp(-15.0 * delta))
	if _cam:
		_cam.rotation.x = -deg_to_rad(_cam_kick)
	for id in _ghosts:
		var g: Dictionary = _ghosts[id]
		if float(g.flash_t) > 0.0:
			g.flash_t = float(g.flash_t) - delta * speed
			(g.flash as Node3D).visible = float(g.flash_t) > 0.0
	if _draw:
		_draw.queue_redraw()
	if _pt >= _t_end:
		_end_playback()


func _apply_frames(t: float) -> void:
	var frames: Array = _clip.frames
	while _frame_i < frames.size() - 2 and float(frames[_frame_i + 1][0]) <= t:
		_frame_i += 1
	var a: Array = frames[_frame_i]
	var b: Array = frames[mini(_frame_i + 1, frames.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var w := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	var pa: Dictionary = a[1]
	var pb: Dictionary = b[1]
	for id in _ghosts:
		var sa: Variant = pa.get(id)
		var sb: Variant = pb.get(id)
		if sa == null and sb == null:
			(_ghosts[id].root as Node3D).visible = false
			continue
		_pose_ghost(_ghosts[id], sa, sb, w, id == int(_clip.info.get("k", 0)))
	var nades: PackedVector3Array = a[2] if w < 0.5 else b[2]
	for i in _nades.size():
		_nades[i].visible = i < nades.size()
		if i < nades.size():
			_nades[i].global_position = nades[i]


func _pose_ghost(g: Dictionary, sa: Variant, sb: Variant, w: float, is_killer: bool) -> void:
	var s: Array = sa if sa != null else sb
	if sa != null and sb != null and w >= 0.5:
		s = sb
	var alive := bool(s[5])
	var root: Node3D = g.root
	# The killer's camera stays where they were if they die first (a grenade still in the air).
	root.visible = alive
	if not alive:
		return
	var pos: Vector3 = s[0]
	var yaw := float(s[1])
	var pitch := float(s[2])
	var crouch := float(s[3])
	if sa != null and sb != null and bool(sa[5]) == bool(sb[5]):
		var a: Array = sa
		var b: Array = sb
		if (a[0] as Vector3).distance_to(b[0]) < SNAP_JUMP:
			pos = (a[0] as Vector3).lerp(b[0], w)
			yaw = lerp_angle(float(a[1]), float(b[1]), w)
			pitch = lerpf(float(a[2]), float(b[2]), w)
			crouch = lerpf(float(a[3]), float(b[3]), w)
	root.global_position = pos
	root.rotation = Vector3(0.0, yaw, 0.0)
	var head: Node3D = g.head
	head.position.y = lerpf(Player.STAND_EYE, Player.CROUCH_EYE, crouch)
	head.rotation.x = pitch
	if not is_killer:
		Player.pose_body(g.body, crouch)
	_ghost_weapon(g, int(s[4]))


func _run_events(to_t: float, speed: float) -> void:
	var events: Array = _clip.events
	var info: Dictionary = _clip.info
	var killer := int(info.get("k", 0))
	var victim := int(info.get("v", 0))
	while _ev_i < events.size() and float(events[_ev_i][0]) <= to_t:
		var e: Array = events[_ev_i]
		_ev_i += 1
		match str(e[1]):
			"fire":
				_replay_fire(int(e[2]), StringName(e[3]), speed, int(e[2]) == killer)
			"tracer":
				var from: Vector3 = e[3]
				var g: Variant = _ghosts.get(int(e[2]))
				if int(e[2]) == killer and g != null:
					from = (g.muzzle as Node3D).global_position # line up with the replayed viewmodel
				_tracer(from, e[4], StringName(e[5]), TRACER_LIFE / speed)
			"hurt":
				if int(e[2]) == victim:
					_mark(false, false)
					_sfx_hit.play()
			"death":
				if int(e[2]) == victim:
					var hs := bool(info.get("hs", false))
					_mark(true, hs)
					if hs:
						_sfx_head.play()
					_sfx_kill.play()
			"boom":
				Grenade.play_boom(e[2])


func _replay_fire(peer_id: int, weapon_id: StringName, speed: float, is_killer: bool) -> void:
	var g: Variant = _ghosts.get(peer_id)
	if g == null:
		return
	var def := Game.weapon_def(weapon_id)
	var sfx: AudioStreamPlayer3D = g.sfx
	if def and def.fire_sound:
		sfx.stream = def.fire_sound
		sfx.pitch_scale = randf_range(0.95, 1.05) * (0.72 if speed < 1.0 else 1.0)
		sfx.play()
	g.flash_t = FLASH_LIFE
	(g.flash as Node3D).visible = true
	if is_killer and def:
		_cam_kick += def.kick_pitch_deg * 0.6


func _mark(killed: bool, headshot: bool) -> void:
	_hit_t = 0.35 if killed or headshot else 0.15
	_hit_kill = killed
	_hit_head = headshot


func _end_playback() -> void:
	_playing = false
	_free_ghosts()
	if _overlay:
		_overlay.queue_free()
		_overlay = null
		_draw = null
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	if _hud and is_instance_valid(_hud):
		_hud.visible = _hud_was_visible
	_hud = null
	if _prev_cam and is_instance_valid(_prev_cam) and _prev_cam.is_inside_tree():
		_prev_cam.current = true
	_prev_cam = null
	_clip = {}


# --- Scene for the replay: ghosts, grenades, overlay ---

## A ghost is a copy of the pawn's drawn body plus a head pivot and a gun. The killer's has a camera
## and the gun as a viewmodel instead of a body. Nothing here has collision or game logic.
func _build_ghosts(killer: int) -> void:
	_cam = null
	var scene := get_tree().current_scene
	var packed := load("res://scenes/player.tscn") as PackedScene
	if scene == null or packed == null:
		return
	var tmpl := packed.instantiate()
	var body_src := tmpl.get_node("BodyMesh") as Node3D
	var tag_src := tmpl.get_node("Nametag") as Label3D
	var weapon_root := tmpl.get_node("Head/Camera3D/WeaponRoot") as Node3D
	_rest = weapon_root.position
	var fx_src: Array[Node3D] = [
		tmpl.get_node("Head/Camera3D/WeaponRoot/Muzzle/Flash") as Node3D,
		tmpl.get_node("Head/Camera3D/WeaponRoot/Muzzle/FlashLight") as Node3D,
	]
	var mats: Array[StandardMaterial3D] = []
	var torso := body_src.get_node("Torso") as MeshInstance3D
	for team in 2:
		var src := torso.get_surface_override_material(0) as StandardMaterial3D
		var mat := src.duplicate() as StandardMaterial3D if src else StandardMaterial3D.new()
		Player.paint_body(mat, team)
		mats.append(mat)
	var ids := {}
	for f in _clip.frames:
		for id in (f[1] as Dictionary):
			ids[id] = true
	var info: Dictionary = _clip.info
	for id in ids:
		var meta: Array = _clip.meta.get(id, ["", 0])
		var team := clampi(int(meta[1]), 0, 1)
		var g := _make_ghost(scene, body_src, fx_src, mats[team], id == killer)
		_ghosts[id] = g
		if id == killer:
			_cam = g.pivot as Camera3D
		if id == int(info.get("v", 0)):
			var tag := tag_src.duplicate() as Label3D
			tag.text = str(info.get("vn", meta[0]))
			tag.modulate = Player.TEAM_COLORS[clampi(int(info.get("vt", team)), 0, 1)]
			tag.no_depth_test = true
			tag.visible = true
			(g.root as Node3D).add_child(tag)
	tmpl.free()
	for i in 4:
		var nade := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		nade.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.45, 0.18)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.8, 0.25)
		mat.emission_energy_multiplier = 1.4
		nade.material_override = mat
		nade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nade.visible = false
		scene.add_child(nade)
		_nades.append(nade)


func _make_ghost(
	scene: Node, body_src: Node3D, fx_src: Array[Node3D], mat: StandardMaterial3D, is_killer: bool
) -> Dictionary:
	var root := Node3D.new()
	root.name = "KillcamGhost"
	scene.add_child(root, true)
	var body := body_src.duplicate() as Node3D
	for c in body.get_children():
		var part := c as MeshInstance3D
		if part:
			part.set_surface_override_material(0, mat)
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.visible = not is_killer # first person: no own body, like the live game
	root.add_child(body)
	var head := Node3D.new()
	head.position.y = Player.STAND_EYE
	root.add_child(head)
	var pivot: Node3D
	if is_killer:
		var cam := Camera3D.new()
		cam.fov = CameraFeel.BASE_FOV
		cam.near = 0.03
		pivot = cam
	else:
		pivot = Node3D.new()
	head.add_child(pivot)
	var gun_root := Node3D.new()
	pivot.add_child(gun_root)
	var muzzle := Node3D.new()
	gun_root.add_child(muzzle)
	# The pawn's own muzzle flash and light, shown together for FLASH_LIFE.
	var flash := Node3D.new()
	flash.visible = false
	muzzle.add_child(flash)
	for src in fx_src:
		var fx := src.duplicate() as Node3D
		fx.position = Vector3.ZERO
		fx.visible = true
		flash.add_child(fx)
	var sfx := AudioStreamPlayer3D.new()
	sfx.bus = "SFX"
	sfx.volume_db = -6.0
	sfx.unit_size = 12.0
	sfx.max_distance = 110.0
	sfx.attenuation_filter_cutoff_hz = 4000.0
	sfx.max_polyphony = 6
	head.add_child(sfx)
	return {
		"root": root, "body": body, "head": head, "pivot": pivot, "gun_root": gun_root,
		"muzzle": muzzle, "flash": flash, "sfx": sfx, "model": null, "wpn": -1, "flash_t": 0.0,
	}


func _ghost_weapon(g: Dictionary, index: int) -> void:
	index = clampi(index, 0, Weapon.LOADOUT.size() - 1)
	if int(g.wpn) == index:
		return
	g.wpn = index
	if g.model != null and is_instance_valid(g.model):
		(g.model as Node).queue_free()
	var def: WeaponDef = Weapon.LOADOUT[index]
	var packed := Weapon.MODEL_SCENES.get(def.id) as PackedScene
	if packed == null:
		g.model = null
		return
	var model := packed.instantiate() as Node3D
	Weapon.no_shadows(model)
	var gun_root: Node3D = g.gun_root
	gun_root.add_child(model)
	var fit := Weapon.fit_model(model, def.id, _rest)
	gun_root.position = fit.root
	(g.muzzle as Node3D).position = fit.muzzle
	g.model = model


func _free_ghosts() -> void:
	for id in _ghosts:
		var root: Node3D = _ghosts[id].root
		if is_instance_valid(root):
			root.queue_free()
	_ghosts.clear()
	for n in _nades:
		if is_instance_valid(n):
			n.queue_free()
	_nades.clear()
	_cam = null


func _tracer(from: Vector3, to: Vector3, weapon_id: StringName, life: float) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var def := Game.weapon_def(weapon_id)
	var width := def.tracer_width if def else 0.02
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.65, 0.2) if weapon_id == &"shotgun" else Color(1.0, 0.82, 0.28)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 3.0
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mesh_inst)
	mesh_inst.global_position = (from + to) * 0.5
	mesh_inst.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
	get_tree().create_timer(life).timeout.connect(mesh_inst.queue_free)


## Live pawns, grenades, and the HUD go away for the replay; _end_playback brings them back.
func _hide_live_world() -> void:
	_hidden.clear()
	_hide_new_pawns()
	_hud = get_tree().get_first_node_in_group("hud") as CanvasItem
	if _hud:
		_hud_was_visible = _hud.visible
		_hud.visible = false


## Also catches pawns that spawn during the replay (a join, a replacement bot).
func _hide_new_pawns() -> void:
	for group in ["player", "grenade"]:
		for n in get_tree().get_nodes_in_group(group):
			var n3 := n as Node3D
			if n3 and n3.visible:
				n3.visible = false
				_hidden.append(n3)


func _build_overlay(info: Dictionary) -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	var full := Control.new()
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(full)
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw.bind(_draw))
	full.add_child(_draw)
	var top := _bar(full, true)
	var title := _label("FINAL KILLCAM", 34, Color(1, 1, 1))
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	var bottom := _bar(full, false)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	var kt := clampi(int(info.get("kt", 0)), 0, 1)
	var vt := clampi(int(info.get("vt", 1)), 0, 1)
	row.add_child(_label(str(info.get("kn", "?")), 26, Player.TEAM_COLORS[kt]))
	var icon := TextureRect.new()
	var wid := StringName(str(info.get("w", "rifle")))
	icon.texture = Hud._FEED_ICONS.get(wid, Hud._FEED_ICONS[&"rifle"])
	icon.custom_minimum_size = Vector2(84, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	row.add_child(_label(str(info.get("vn", "?")), 26, Player.TEAM_COLORS[vt]))
	if bool(info.get("hs", false)):
		row.add_child(_label("HEADSHOT", 20, Color(1.0, 0.86, 0.2)))


func _bar(parent: Control, top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.82)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_right = 1.0
	if top:
		bar.anchor_bottom = 0.0
		bar.offset_bottom = BAR_H
	else:
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.offset_top = -BAR_H
	parent.add_child(bar)
	return bar


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The killer's crosshair and hit markers, like the HUD draws them.
func _on_draw(canvas: Control) -> void:
	var c := canvas.size * 0.5
	var col := Color(0.95, 0.95, 0.95, 0.85)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		canvas.draw_line(c + d * 5.0, c + d * 13.0, col, 2.0, true)
	if _hit_t <= 0.0:
		return
	var a := clampf(_hit_t / 0.12, 0.0, 1.0)
	var hit_col := Color(1, 1, 1, a)
	if _hit_kill:
		hit_col = Color(1.0, 0.22, 0.18, a)
	elif _hit_head:
		hit_col = Color(1.0, 0.86, 0.2, a)
	var s := 13.0 if _hit_kill or _hit_head else 9.0
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		canvas.draw_line(c + d * s, c + d * s * 0.35, hit_col, 2.4, true)
