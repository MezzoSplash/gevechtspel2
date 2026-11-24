class_name KillcamDirector
extends RefCounted
## #317: the killcam's cutting rules, pulled out of `scripts/killcam.gd` (#258). Pure static functions
## over buffers in the recorder's own format (see `Killcam._snapshot`), so they can be checked without a
## match (`tools/check_killcam_director`). No state, no nodes, nothing on the wire: `Killcam` keeps the
## buffer, the playback and the old function names as wrappers, so callers did not change.
##
## A snapshot: [t, {peer: [pos, yaw, pitch, crouch, weapon, alive, move_fx, flip, throw, reload]},
## nades, knives]. An event: [t, kind, a, b, c, d].

const PRE := 5.0 # the replay starts this long before the kill
const POST := 2.0 # and runs this long after it; the server waits POST before it sends "play"
const SLOW_FROM := 0.3 # slow motion from this long before the kill
const SLOW_TO := 0.25 # until this long after it
const SLOW := 0.35 # playback speed in the slow part
const LOOKBACK := 9.0 # s of history the start may reach back into; Killcam.KEEP has to cover it
const MIN_LEN := 2.5 # s: a clip is never shorter than this, even when nothing happened
const LEAD_IN := 0.35 # s of run-up before the first action frame
const DULL_SPEED := 4.0 # m/s: below this, and without a move, the killer is just walking
const DULL_PAD := 0.35 # s around an event that still counts as action
const CHAIN_GAP := 0.9 # s of nothing that ends the run leading into the kill
const FAST := 2.5 # playback speed over a dull stretch
const FOLD_MIN := 0.5 # s: only dull stretches longer than this are compressed
const VHS_FADE := 0.18 # s the speed-up overlay fades in and out over
const RUNUP_KEEP := 1.5
const MAX_RUNUP := 3.0
const KILL_RATE_MIN := 0.12


static func play_length() -> float:
	return (PRE - SLOW_FROM) + (SLOW_FROM + SLOW_TO) / SLOW + (POST - SLOW_TO)


## #258: the killer's horizontal speed between the previous snapshot and this one, in m/s.
static func killer_speed(frames: Array, i: int, killer: int) -> float:
	if i <= 0 or i >= frames.size():
		return 0.0
	var a: Variant = (frames[i - 1][1] as Dictionary).get(killer)
	var b: Variant = (frames[i][1] as Dictionary).get(killer)
	if a == null or b == null:
		return 0.0
	var dt := float(frames[i][0]) - float(frames[i - 1][0])
	if dt <= 0.0001:
		return 0.0
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	return Vector2(pb.x - pa.x, pb.z - pa.z).length() / dt


## #258: is this event about the killer or the victim? In a match with bots there is always a shot or a
## hit going on somewhere, so counting every event made "dull" almost impossible and the clip never got
## cut. A boom carries a position, not a peer, so it cannot be attributed and does not count.
static func event_hits(e: Array, killer: int, victim: int) -> bool:
	if e.size() < 3 or typeof(e[2]) != TYPE_INT:
		return false
	var id := int(e[2])
	return (killer != 0 and id == killer) or (victim != 0 and id == victim)


## #258: is the killer doing something worth watching on frame `i`?
static func action_at(frames: Array, events: Array, i: int, killer: int, victim := 0) -> bool:
	if i < 0 or i >= frames.size():
		return false
	var st: Variant = (frames[i][1] as Dictionary).get(killer)
	if st == null:
		return false
	if int(st[6]) != Player.MOVE_NONE: # any move: wallrun, slide, dive, roll, surf
		return true
	if killer_speed(frames, i, killer) >= DULL_SPEED:
		return true
	var t := float(frames[i][0])
	for e in events:
		if absf(float(e[0]) - t) <= DULL_PAD and event_hits(e, killer, victim):
			return true
	return false


## #258: where the replay starts: back to the first frame of the run that ends in the kill, with LEAD_IN
## of run-up. Never later than MIN_LEN before the kill (a clip that is only a second long leaves you
## staring at a held frame for the rest of the replay), and a clip with nothing in it starts there too.
static func action_start(frames: Array, events: Array, t_kill: float, killer: int, victim := 0) -> float:
	if frames.is_empty():
		return t_kill - MIN_LEN
	var floor_t := t_kill - LOOKBACK
	var earliest := t_kill
	var last_action := t_kill
	for i in range(frames.size() - 1, -1, -1):
		var t := float(frames[i][0])
		if t < floor_t:
			break
		if not action_at(frames, events, i, killer, victim):
			continue
		if last_action - t > CHAIN_GAP:
			break # the run that leads into the kill starts after this gap
		last_action = t
		earliest = t
	if earliest >= t_kill:
		return clampf(t_kill - MIN_LEN, floor_t, t_kill)
	# At least MIN_LEN of clip, even when the run itself is shorter: the replay has to have body.
	return clampf(minf(earliest - LEAD_IN, t_kill - MIN_LEN), floor_t, t_kill)


## #258: the stretches where nothing happens, as Vector2(start, end) seconds. Only runs longer than
## FOLD_MIN are returned, so the playback speed does not flicker from frame to frame.
static func dull_runs(frames: Array, events: Array, killer: int, victim := 0) -> Array[Vector2]:
	var runs: Array[Vector2] = []
	var start := -1.0
	for i in frames.size():
		var t := float(frames[i][0])
		if action_at(frames, events, i, killer, victim):
			if start >= 0.0:
				_close_run(runs, start, t)
				start = -1.0
		elif start < 0.0:
			start = t
	if start >= 0.0 and not frames.is_empty():
		_close_run(runs, start, float(frames[frames.size() - 1][0]))
	return runs


static func _close_run(runs: Array[Vector2], a: float, b: float) -> void:
	if b - a >= FOLD_MIN:
		runs.append(Vector2(a, b))


## #258: playback rate at `t`: slow motion right around the kill (unchanged), FAST over the dull runs,
## 1.0 everywhere else. The kill window wins, so the moment itself is never fast-forwarded.
static func rate_at(t: float, t_kill: float, runs: Array[Vector2]) -> float:
	if t >= t_kill - SLOW_FROM and t < t_kill + SLOW_TO:
		return SLOW
	for r in runs:
		if t >= r.x and t < r.y:
			return FAST
	return 1.0


## #258: how much of the VHS fast-forward overlay is on, 0..1. One inside a dull run and ramping over
## VHS_FADE at both ends, so the tape reads as an effect and not as a broken frame. Nothing on the kill.
static func vhs_amount(t: float, t_kill: float, runs: Array[Vector2]) -> float:
	if t >= t_kill - SLOW_FROM and t < t_kill + SLOW_TO:
		return 0.0
	for r in runs:
		if t >= r.x - VHS_FADE and t <= r.y + VHS_FADE:
			var a := clampf((t - (r.x - VHS_FADE)) / VHS_FADE, 0.0, 1.0)
			var b := clampf(((r.y + VHS_FADE) - t) / VHS_FADE, 0.0, 1.0)
			return minf(a, b)
	return 0.0


## #258: the combo payout while the replay runs: 0 at the start of the clip, the full bank exactly at the
## kill, so the number lands with the shot instead of being a static caption.
static func ticker_value(bank: int, t: float, t_start: float, t_kill: float) -> int:
	if bank <= 0 or t_kill <= t_start:
		return bank
	var p := clampf((t - t_start) / (t_kill - t_start), 0.0, 1.0)
	return int(round(float(bank) * smoothstep(0.0, 1.0, p)))
