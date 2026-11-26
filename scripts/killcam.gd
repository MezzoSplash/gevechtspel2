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
const KEEP := 14.0 # seconds of history: LOOKBACK + POST + slice margin, with room to spare
const GRACE := 0.3 # server: room for latency before it unlocks
const TRACER_LIFE := 0.055
const FLASH_LIFE := 0.05
const BAR_H := 64.0
const SNAP_JUMP := 4.0 # metres between snapshots that count as a teleport (respawn): no blending
const SPECIAL_BANK := 400 # style points from which a landed combo also gets the special sting
## #317: the cutting rules (where the clip starts, which stretches are dull, how fast they play, the slow
## motion around the kill) live in `scripts/killcam_director.gd` — pure functions over the buffer. These
## aliases keep every `Killcam.PRE`-style name working for the player, the checks and `total_time`.
const PRE := KillcamDirector.PRE
const POST := KillcamDirector.POST
const SLOW_FROM := KillcamDirector.SLOW_FROM
const SLOW_TO := KillcamDirector.SLOW_TO
const SLOW := KillcamDirector.SLOW
const LOOKBACK := KillcamDirector.LOOKBACK
const MIN_LEN := KillcamDirector.MIN_LEN
const LEAD_IN := KillcamDirector.LEAD_IN
const DULL_SPEED := KillcamDirector.DULL_SPEED
const DULL_PAD := KillcamDirector.DULL_PAD
const CHAIN_GAP := KillcamDirector.CHAIN_GAP
const FAST := KillcamDirector.FAST
const FOLD_MIN := KillcamDirector.FOLD_MIN
const VHS_FADE := KillcamDirector.VHS_FADE
const KILL_RATE_MIN := KillcamDirector.KILL_RATE_MIN
const RUNUP_KEEP := KillcamDirector.RUNUP_KEEP
const MAX_RUNUP := KillcamDirector.MAX_RUNUP

var _clock := 0.0 # recording time; pauses with the tree like the game does
var _snap_t := 0.0
var _frames: Array = [] # [t, {peer_id: [pos, yaw, pitch, crouch, weapon_index, alive, move_fx]}, grenade positions]
var _events: Array = [] # [t, kind, a, b, c, d]
var _meta: Dictionary = {} # peer_id -> [name, team]
var _clips: Dictionary = {} # victim peer_id -> their last death, kept for rounds that end on the clock
var _pending_clips: Array = [] # [victim peer_id, death time]
# Best trickshot of the round (Game.best_trick): the server flags each new best; we keep its replay here.
var _trick_wait: Dictionary = {} # victim peer_id -> [trick_id, noted at], until that victim's death is recorded
## #88: a wait older than this is stale (the death never came, or came first). Without the expiry a later,
## ordinary death of the same victim was saved as the "best trickshot".
const TRICK_WAIT_MAX := 1.0
const TRICK_DEATH_BEFORE := 0.25 # a death this recent (s) before note_trick belongs to that trick
var _trick_deaths: Array = [] # [trick_id, death time] waiting for POST before they are sliced
var _trick_clip: Dictionary = {} # the sliced replay of the latest best trick ("trick_id" key)

var _playing := false
var _clip: Dictionary = {}
var _pt := 0.0 # playback position on the recording timeline
var _dull: Array[Vector2] = [] # dull stretches of the current clip (#258)
var _real_t := 0.0 # real seconds spent in the replay: the tail is held until play_length() (#258)
var _t_start := 0.0 # where the replay starts, for the climbing payout (#258)
var _kill_rate := SLOW # planned slow-motion rate around the kill (#258)
var _runup := 1.0 # > 1: the run-up before the last seconds is compressed to fit the wall clock (#258)
var _t_kill := 0.0
var _t_end := 0.0
var _frame_i := 0
var _ev_i := 0
var _ghosts: Dictionary = {} # peer_id -> ghost parts (see _make_ghost)
var _nades: Array[GrenadeLook] = []
var _knives: Array[Node3D] = [] # replay copies of throwing knives (frame slot 3: Transform3D each)
var _hidden: Array[Node3D] = []
var _hud: CanvasItem
var _hud_was_visible := false
var _prev_cam: Camera3D
var _cam: Camera3D
var _cam_kick := 0.0
var _rest := Vector3(0.24, -0.18, -0.42)
var _overlay: CanvasLayer
var _draw: Control
var _title: Label # the top-bar title, which climbs with the combo (#258)
var _hit_t := 0.0
var _hit_kill := false
var _hit_head := false
var _sfx_hit: AudioStreamPlayer
var _sfx_head: AudioStreamPlayer
var _sfx_kill: AudioStreamPlayer
var _sfx_land: AudioStreamPlayer # the Tony Hawk "landed" sting on the kill (#258)
var _sfx_special: AudioStreamPlayer


func _ready() -> void:
	_sfx_hit = _ui_sound("res://assets/sounds/hit.wav", -6.0)
	_sfx_head = _ui_sound("res://assets/sounds/headshot.wav", -5.0)
	_sfx_kill = _ui_sound("res://assets/sounds/kill.wav", -3.0)
	_sfx_land = _ui_sound("res://assets/sounds/combo_land.wav", -2.0)
	_sfx_special = _ui_sound("res://assets/sounds/combo_special.wav", -1.0)


func _ui_sound(path: String, db: float) -> AudioStreamPlayer:
	var s := AudioStreamPlayer.new()
	s.stream = load(path)
	s.volume_db = db
	s.bus = "UI"
	add_child(s)
	return s


## Length of the replay itself (real seconds), the same on every machine.
## #317: the cutting rules live in `scripts/killcam_director.gd` (pure functions, checked by
## tools/check_killcam_director). These wrappers keep the names this file, the checks and the player used.
static func play_length() -> float:
	return KillcamDirector.play_length()


static func killer_speed(frames: Array, i: int, killer: int) -> float:
	return KillcamDirector.killer_speed(frames, i, killer)


static func event_hits(e: Array, killer: int, victim: int) -> bool:
	return KillcamDirector.event_hits(e, killer, victim)


static func action_at(frames: Array, events: Array, i: int, killer: int, victim := 0) -> bool:
	return KillcamDirector.action_at(frames, events, i, killer, victim)


static func action_start(frames: Array, events: Array, t_kill: float, killer: int, victim := 0) -> float:
	return KillcamDirector.action_start(frames, events, t_kill, killer, victim)


static func dull_runs(frames: Array, events: Array, killer: int, victim := 0) -> Array[Vector2]:
	return KillcamDirector.dull_runs(frames, events, killer, victim)


static func rate_at(t: float, t_kill: float, runs: Array[Vector2]) -> float:
	return KillcamDirector.rate_at(t, t_kill, runs)


static func vhs_amount(t: float, t_kill: float, runs: Array[Vector2]) -> float:
	return KillcamDirector.vhs_amount(t, t_kill, runs)


static func ticker_value(bank: int, t: float, t_start: float, t_kill: float) -> int:
	return KillcamDirector.ticker_value(bank, t, t_start, t_kill)


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
	_trick_wait.clear()
	_trick_deaths.clear()
	_trick_clip = {}
	_clock = 0.0
	_snap_t = 0.0


# --- Recording ---
# #317 step 2: het opnemen (notities, snapshots, slice) zit in KillcamRecorder. Wat buiten dit bestand
# wordt aangeroepen blijft hier als dunne wrapper staan.

func note_fire(peer_id: int, weapon_id: StringName) -> void:
	KillcamRecorder.note_fire(self, peer_id, weapon_id)


func note_tracer(peer_id: int, from: Vector3, to: Vector3, weapon_id: StringName) -> void:
	KillcamRecorder.note_tracer(self, peer_id, from, to, weapon_id)


func note_hurt(peer_id: int) -> void:
	KillcamRecorder.note_hurt(self, peer_id)


func note_death(peer_id: int) -> void:
	KillcamRecorder.note_death(self, peer_id)


## Game._apply_trick: this kill is the round's new best trickshot. Its victim's death comes right after
## (same tick on the server, the next reliable message on clients).
func note_trick(trick_id: int, victim_peer_id: int) -> void:
	KillcamRecorder.note_trick(self, trick_id, victim_peer_id)


func note_boom(pos: Vector3, heavy := false) -> void:
	KillcamRecorder.note_boom(self, pos, heavy)


## tools/check_killcam_roll: the snapshot the checks read.
func _snapshot() -> void:
	KillcamRecorder.snapshot(self)


func _process(delta: float) -> void:
	if _playing:
		_tick_playback(delta)
		return
	if not KillcamRecorder.should_record(self):
		return
	_clock += delta
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = maxf(_snap_t + 1.0 / RATE, 0.0)
		KillcamRecorder.snapshot(self)
	var cut := _clock - KEEP
	while not _frames.is_empty() and float(_frames[0][0]) < cut:
		_frames.pop_front()
	while not _events.is_empty() and float(_events[0][0]) < cut:
		_events.pop_front()
	while not _pending_clips.is_empty() and _clock >= float(_pending_clips[0][1]) + POST + 0.05:
		var entry: Array = _pending_clips.pop_front()
		_clips[int(entry[0])] = KillcamRecorder.slice(self, float(entry[1]))
	while not _trick_deaths.is_empty() and _clock >= float(_trick_deaths[0][1]) + POST + 0.05:
		var td: Array = _trick_deaths.pop_front()
		_trick_clip = KillcamRecorder.slice(self, float(td[1]))
		_trick_clip["trick_id"] = int(td[0])


# --- Playback ---

func _start_playback(info: Dictionary) -> void:
	if Game.is_dedicated or _playing or typeof(info) != TYPE_DICTIONARY:
		return
	var clip := {}
	if info.has("trick_id"):
		# The round's best trickshot. Not recorded here (joined later): the last kill instead.
		clip = KillcamRecorder.trick_clip_for(self, int(info.trick_id))
		if not KillcamRecorder.clip_usable(self, clip, int(info.get("k", 0))):
			clip = {}
			info = info.get("fallback", {})
			if typeof(info) != TYPE_DICTIONARY or info.is_empty():
				return
	var killer := int(info.get("k", 0))
	if clip.is_empty():
		clip = KillcamRecorder.find_clip(self, int(info.get("v", 0)))
	# Joined too late, or the kill fell out of the buffer: no replay. The lock still holds.
	if not KillcamRecorder.clip_usable(self, clip, killer):
		return
	_clip = clip
	_clip["info"] = info
	var frames: Array = clip.frames
	var victim := int(info.get("v", 0))
	_t_kill = float(clip.t_kill)
	_t_end = minf(_t_kill + POST, float(frames[frames.size() - 1][0]))
	_real_t = 0.0
	# #258: fit the clip to the wall clock — start at the run that ends in the kill, pull in earlier
	# footage (played as tape) when the replay would be short, and spend the rest on the kill's slow motion.
	_plan_playback(killer, victim)
	_frame_i = 0
	_ev_i = 0
	var events: Array = clip.events
	while _ev_i < events.size() and float(events[_ev_i][0]) < _pt:
		_ev_i += 1 # recorded before our first snapshot (late join): nothing to attach them to
	_cam_kick = 0.0
	_hit_t = 0.0
	KillcamPuppets.build_ghosts(self, killer)
	if _cam == null:
		KillcamPuppets.free_ghosts(self)
		_clip = {}
		return
	KillcamPuppets.hide_live_world(self)
	KillcamOverlay.build(self, info)
	_prev_cam = get_viewport().get_camera_3d()
	_cam.current = true
	_playing = true
	KillcamPuppets.apply_frames(self, _pt)


func _speed_at(t: float) -> float:
	return _rate(t)


## #258: the one playback rate: the planned slow motion around the kill, the director's FAST over the
## dull stretches, and — when the clip still would not fit the wall clock — the run-up before the last
## seconds is compressed as well. That is what keeps a long chain from being cut off before the kill.
func _rate(t: float) -> float:
	if t >= _t_kill - SLOW_FROM and t < _t_kill + SLOW_TO:
		return _kill_rate
	var base := Killcam.rate_at(t, _t_kill, _dull)
	if _runup > 1.0 and t < _t_kill - RUNUP_KEEP:
		base *= _runup
	return base


## #258: the wall clock a slice of the clip takes at the current rates.
func _real_between(t0: float, t1: float) -> float:
	var total := 0.0
	var frames: Array = _clip.frames
	for i in range(frames.size() - 1):
		var t := float(frames[i][0])
		if t < t0 or t >= t1:
			continue
		var dt := minf(float(frames[i + 1][0]) - t, t1 - t)
		if dt <= 0.0:
			continue
		total += dt / _rate(t)
	return total


## #258: how long the replay takes at the current rates.
func _real_for() -> float:
	return _real_between(_pt, _t_end)


## #258: the wall clock the last RUNUP_KEEP seconds before the kill take, plus the tail after it: the
## part that always keeps its own speed, so the ending reads at 1x no matter how much was compressed.
func _fixed_real() -> float:
	return _real_between(_t_kill - RUNUP_KEEP, _t_end)


## #258: fit the clip to the wall clock. The director's start is the run that ends in the kill; when the
## replay would be shorter than play_length() (because the dead air is fast-forwarded), earlier footage is
## pulled in — it plays as tape, which is exactly what the fast-forward is for — and whatever is still
## missing is spent on a longer slow-motion kill. And when the clip is too *long* to fit (a long chain at
## 1x used to run past the server's unlock and cut the kill off), the run-up before the last seconds is
## compressed instead. Sets `_pt`, `_t_start`, `_dull`, `_kill_rate` and `_runup`.
func _plan_playback(killer: int, victim: int) -> void:
	var span := SLOW_FROM + SLOW_TO
	var floor_t := _t_kill - LOOKBACK
	if not _clip.frames.is_empty():
		floor_t = maxf(floor_t, float((_clip.frames as Array)[0][0])) # no tape before the first snapshot
	var start := Killcam.action_start(_clip.frames, _clip.events, _t_kill, killer, victim)
	_kill_rate = SLOW
	_runup = 1.0
	var need := 0.0
	for attempt in 5:
		_pt = start
		_t_start = start
		_dull = Killcam.dull_runs(_clip.frames, _clip.events, killer, victim)
		# need = the wall clock left for the kill window (its own cost at the current rate is removed).
		need = play_length() - (_real_for() - span / _kill_rate)
		if absf(need) <= span:
			break # the clip fits the wall clock at the planned rates
		if need > 0.0:
			# 1) The replay is too short: earlier footage buys wall clock, one clip-second of tape
			# plays at 1/FAST.
			var buy := minf(need * Killcam.FAST, start - floor_t)
			if buy > 0.01:
				start = maxf(floor_t, start - buy)
				continue
		# 2) No buffer left and the replay is too short, or the clip is too long to fit (a long chain at
		# 1x used to run past the server's unlock and cut the kill off): compress the run-up so the kill
		# is always shown. The last RUNUP_KEEP seconds and the kill window keep their own speed; a
		# leftover that the run-up cannot pay for becomes the kill's slow motion (floored at
		# KILL_RATE_MIN), so the freeze is at most a beat.
		var budget := maxf(play_length() - _fixed_real(), 0.05)
		_runup = clampf(_real_between(_pt, _t_kill - RUNUP_KEEP) / budget, 1.0, MAX_RUNUP)
		need = play_length() - (_real_for() - span / _kill_rate)
		break
	# The kill window takes whatever wall clock is left: deep slow motion when there is a lot of it
	# (KILL_RATE_MIN), and up to real time when the clip was mostly tape. A full-window replay computes to
	# exactly the old SLOW.
	_kill_rate = clampf(span / maxf(need, 0.01), KILL_RATE_MIN, 1.0) if need > 0.0 else SLOW


## #258: how much of the tape overlay is on: the VHS of the dull stretches, and the same look when the
## run-up itself is compressed — any speed-up has to read the same way.
func _tape_amount(t: float) -> float:
	var a := Killcam.vhs_amount(t, _t_kill, _dull)
	if _runup > 1.0 and t < _t_kill - RUNUP_KEEP:
		a = maxf(a, clampf((_runup - 1.0) / 0.5, 0.0, 1.0))
	return a


func _update_title() -> void:
	KillcamOverlay.update_title(self)


func _tick_playback(delta: float) -> void:
	delta = minf(delta, 0.1)
	_real_t += delta
	var speed := _speed_at(_pt)
	if _pt < _t_end:
		_pt = minf(_pt + delta * speed, _t_end)
	KillcamPuppets.apply_frames(self, _pt)
	_run_events(_pt, speed)
	_update_title()
	KillcamPuppets.hide_new_pawns(self)
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
	# #258: the clip may be shorter than play_length() because of the fast-forward, so the last frame is
	# held until the replay has lasted as long as the server expects. Same wall clock, and the kill gets
	# a held beat for free.
	if _pt >= _t_end and _real_t >= play_length() - 0.05:
		_end_playback()


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
				KillcamPuppets.tracer(self, from, e[4], StringName(e[5]), TRACER_LIFE / speed)
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
					_play_landed(info)
			"boom":
				Grenade.play_boom(e[2], e.size() > 3 and bool(e[3]))


## #258: the Tony Hawk "landed" beat. The combo sounds the HUD already uses, pitched up a little with the
## size of the payout, so the kill reads as a combo that *landed* instead of just a shot that hit. The
## special sting comes in a beat later, and only for a big bank; no new assets (#135).
func _play_landed(info: Dictionary) -> void:
	if _sfx_land == null:
		return
	var bank := int(info.get("bank", 0))
	if bank <= 0:
		return
	_sfx_land.pitch_scale = clampf(0.94 + float(bank) / 5000.0, 0.94, 1.15)
	_sfx_land.play()
	if bank >= SPECIAL_BANK and _sfx_special != null:
		# The replay may end before the timer fires (a very short clip): then the sting stays quiet.
		get_tree().create_timer(0.14).timeout.connect(func(): if _playing and _sfx_special != null: _sfx_special.play())


func _replay_fire(peer_id: int, weapon_id: StringName, speed: float, is_killer: bool) -> void:
	var g: Variant = _ghosts.get(peer_id)
	if g == null:
		return
	var def := Game.weapon_def(weapon_id)
	var sfx: AudioStreamPlayer3D = g.sfx
	var shot := WeaponKit.fire_sound(def) # the same sound as the match: the kit's, else the def's
	if shot:
		sfx.stream = shot
		sfx.pitch_scale = randf_range(0.95, 1.05) * (0.72 if speed < 1.0 else 1.0)
		sfx.play()
	var model_flash := Weapon.play_model_shot(g.model as Node3D, speed, def.fire_rate if def else 0.0, def.flash_time if def else 0.045)
	# Model particles replace the plain quad for this shot. flash_t would turn that quad back on.
	if model_flash:
		g.flash_t = 0.0
		(g.flash as Node3D).visible = false
	else:
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
	KillcamPuppets.free_ghosts(self)
	if _overlay:
		_overlay.queue_free()
		_overlay = null
		_draw = null
		_title = null
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

## #317 stap 2: de 2D-laag (balken, titel, crosshair, VHS) zit in KillcamOverlay.
func _on_draw(canvas: Control) -> void:
	KillcamOverlay.on_draw(self, canvas)
