extends Node
## #258 director: the killcam is cut around what the killer did, not around a fixed window.
##   godot --headless res://tools/check_killcam_director.tscn   → "KILLCAM DIRECTOR CHECK OK"
## Synthetic buffers in the recorder's own format (see Killcam._snapshot), so this runs without a match.
## A scene, not a `-s` SceneTree script: Killcam needs the Game autoload to compile.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


## One snapshot: [t, {peer: [pos, yaw, pitch, crouch, weapon, alive, move_fx, flip, throw, reload]}, nades, knives]
func _frame(t: float, pos: Vector3, fx := 0) -> Array:
	return [t, {1: [pos, 0.0, 0.0, 0.0, 0, true, fx, 0.0, 0.0, 0.0]}, PackedVector3Array(), []]


## `walk` seconds of slow walking (+Z, 2 m/s), then `chain` seconds of a wallrun at 11 m/s, then the kill.
func _clip(walk: float, chain: float) -> Dictionary:
	var frames: Array = []
	var t := 0.0
	var z := 0.0
	var step := 1.0 / Killcam.RATE
	while t < walk:
		frames.append(_frame(t, Vector3(0.0, 0.0, z)))
		z += 2.0 * step # 2 m/s: walking
		t += step
	var chain_start := t
	while t < chain_start + chain:
		frames.append(_frame(t, Vector3(0.0, 0.0, z), Player.MOVE_WALLRUN))
		z += 11.0 * step # 11 m/s: wallrun
		t += step
	var t_kill := t
	# The buffer always holds POST after the death (the server waits for it), and the killer keeps moving.
	while t < t_kill + 2.0:
		frames.append(_frame(t, Vector3(0.0, 0.0, z), 0))
		z += 11.0 * step
		t += step
	var events: Array = [[t_kill, "death", 2], [t_kill - 0.15, "fire", 1]]
	return {"t_kill": t_kill, "chain_start": chain_start, "frames": frames, "events": events, "meta": {}}


func _ready() -> void:
	# 1) The clip starts at the chain, not PRE seconds before the kill. A short chain is padded back to
	# MIN_LEN, because a clip that is only a second long would leave a held frame for the rest.
	var c := _clip(6.0, 1.2)
	var start := Killcam.action_start(c.frames, c.events, float(c.t_kill), 1, 2)
	_ok(start <= float(c.chain_start) + 0.05, "the chain is inside the clip (start %.2f s, chain at %.2f)" % [start, float(c.chain_start)])
	_ok(start > float(c.t_kill) - Killcam.PRE, "and later than the old fixed PRE window (%.2f s in)" % (float(c.t_kill) - start))
	_ok(start <= float(c.t_kill) - Killcam.MIN_LEN, "and at least MIN_LEN before the kill (%.2f s)" % (float(c.t_kill) - start))

	# 2) A chain longer than PRE is not cut off at PRE: you get the whole run.
	var c2 := _clip(2.0, 7.0)
	var start2 := Killcam.action_start(c2.frames, c2.events, float(c2.t_kill), 1, 2)
	_ok(start2 < float(c2.t_kill) - Killcam.PRE, "a long chain is not cut off at PRE (%.2f s in)" % (float(c2.t_kill) - start2))
	_ok(start2 >= float(c2.t_kill) - Killcam.LOOKBACK, "and stays inside the lookback")
	_ok(start2 <= float(c2.chain_start) + 0.05, "starting at the chain (%.2f s, chain at %.2f)" % [start2, float(c2.chain_start)])

	# 3) A dull kill with a realistic event list still gets its MIN_LEN. The killer's own shot and the
	# victim's death make the last 0.35 s action; without the MIN_LEN floor the clip would be under a
	# second long and the replay would spend the rest staring at a held frame.
	var dull := _clip(6.0, 0.0)
	var dull_tk := float(dull.t_kill)
	var events3: Array = [[dull_tk - 0.10, "fire", 1], [dull_tk - 0.20, "hurt", 2], [dull_tk, "death", 2],
		[dull_tk - 1.0, "fire", 3], [dull_tk - 2.0, "hurt", 3], [dull_tk - 3.0, "death", 3]]
	var start3 := Killcam.action_start(dull.frames, events3, dull_tk, 1, 2)
	_ok(is_equal_approx(start3, dull_tk - Killcam.MIN_LEN), "a dull kill starts at MIN_LEN (%.2f s in)" % (dull_tk - start3))

	# 4) Events from other players never extend the run: in a bot match there is always a shot somewhere,
	# and without the killer/victim filter the chain would never break and nothing would be dull.
	var foreign: Array = []
	for i in 12:
		foreign.append([dull_tk - 0.5 - 0.5 * float(i), "hurt", 3])
	var start4 := Killcam.action_start(dull.frames, foreign, dull_tk, 1, 2)
	_ok(is_equal_approx(start4, dull_tk - Killcam.MIN_LEN), "foreign events never make the run longer (%.2f s in)" % (dull_tk - start4))
	_ok(Killcam.dull_runs(dull.frames, foreign, 1, 2).size() > 0, "and a busy map still has dull stretches")

	# 5) Speed profile: fast over the walk, 1x on the chain, slow around the kill.
	var runs := Killcam.dull_runs(c.frames, c.events, 1, 2)
	_ok(Killcam.rate_at(2.0, float(c.t_kill), runs) == Killcam.FAST, "the walk is fast-forwarded")
	_ok(Killcam.rate_at(float(c.chain_start) + 0.4, float(c.t_kill), runs) == 1.0, "the wallrun runs at normal speed")
	_ok(Killcam.rate_at(float(c.t_kill), float(c.t_kill), runs) == Killcam.SLOW, "the kill is slow motion")
	_ok(Killcam.rate_at(float(c.t_kill) + Killcam.SLOW_TO + 0.2, float(c.t_kill), runs) == 1.0,
		"the tail after the kill is normal speed")

	# 6) Short dull gaps are not worth compressing (no flickering between 1x and 2.5x).
	var short_gap: Array = [_frame(0.0, Vector3.ZERO), _frame(1.0 / Killcam.RATE, Vector3(0.0, 0.0, 0.05), Player.MOVE_WALLRUN),
		_frame(2.0 / Killcam.RATE, Vector3(0.0, 0.0, 0.1))]
	_ok(Killcam.dull_runs(short_gap, [], 1, 2).is_empty(), "a gap shorter than FOLD_MIN (%.2f s) is not compressed" % Killcam.FOLD_MIN)

	# 7) The VHS fast-forward overlay is on exactly where the replay is compressed, and never on the kill.
	_ok(Killcam.vhs_amount(2.0, float(c.t_kill), runs) > 0.9, "the VHS overlay is on over the walk")
	_ok(is_equal_approx(Killcam.vhs_amount(float(c.chain_start) + 0.4, float(c.t_kill), runs), 0.0),
		"and off on the wallrun")
	_ok(is_equal_approx(Killcam.vhs_amount(float(c.t_kill), float(c.t_kill), runs), 0.0),
		"and off in the slow-motion kill")

	# 8) The combo payout climbs and lands exactly on the kill.
	var bank := 400
	var t0 := 10.0
	var tk := 14.0
	_ok(Killcam.ticker_value(bank, t0, t0, tk) == 0, "the payout starts at 0")
	_ok(Killcam.ticker_value(bank, tk, t0, tk) == bank, "and lands on the full bank at the kill")
	var half := Killcam.ticker_value(bank, 12.0, t0, tk)
	_ok(half > 0 and half < bank, "with a value in between halfway (%d)" % half)
	_ok(Killcam.ticker_value(bank, tk + 5.0, t0, tk) == bank, "and never overshoots")
	_ok(Killcam.ticker_value(0, 12.0, t0, tk) == 0, "no bank, no counter")

	# 9) The recorder's slice reaches LOOKBACK back, so the director has something to find (#258).
	var kc := Game.killcam
	_ok(kc != null, "the game has a killcam to test the slice wiring")
	if kc != null:
		kc._frames = c2.frames.duplicate()
		kc._events = c2.events.duplicate()
		kc._clock = float(c2.t_kill) + 2.0
		var sliced: Dictionary = kc._slice(float(c2.t_kill))
		var first := float((sliced.frames as Array)[0][0])
		_ok(first <= float(c2.t_kill) - Killcam.PRE, "the sliced clip reaches further back than PRE (%.2f s)" % (float(c2.t_kill) - first))
		_ok(is_equal_approx(Killcam.action_start(sliced.frames, sliced.events, float(sliced.t_kill), 1, 2), start2),
			"and the director reads the same start out of it")
		kc._frames = []
		kc._events = []
		kc._clock = 0.0

		# 10) The planner fills play_length(): earlier footage is pulled in as tape and the rest goes into
		# a longer slow-motion kill, so there is no seconds-long freeze at the end of a short clip.
		var long_dull := _clip(9.0, 0.0)
		var ltk := float(long_dull.t_kill)
		var levents: Array = [[ltk - 0.10, "fire", 1], [ltk, "death", 2]]
		kc._clip = long_dull
		kc._events = levents
		kc._t_kill = ltk
		kc._t_end = minf(ltk + Killcam.POST, float((long_dull.frames as Array)[(long_dull.frames as Array).size() - 1][0]))
		kc._plan_playback(1, 2)
		_ok(kc._kill_rate > Killcam.KILL_RATE_MIN and kc._kill_rate <= 1.0,
			"a dull kill plays its slow motion at the rate the wall clock needs (%.2f x)" % kc._kill_rate)
		_ok(absf(kc._real_for() - Killcam.play_length()) < 0.2,
			"and the planned replay fills play_length() (%.2f s of %.2f)" % [kc._real_for(), Killcam.play_length()])
		_ok(kc._pt <= float(ltk) - Killcam.MIN_LEN, "starting at least MIN_LEN back (%.2f s)" % (ltk - kc._pt))
		# A buffer shorter than LOOKBACK (the start of a round) is filled the same way: the kill window
		# takes the leftover wall clock, so there is no long freeze anywhere.
		kc._clip = dull
		kc._events = events3
		kc._t_kill = dull_tk
		kc._t_end = minf(dull_tk + Killcam.POST, float((dull.frames as Array)[(dull.frames as Array).size() - 1][0]))
		kc._plan_playback(1, 2)
		_ok(kc._kill_rate <= 1.0, "the kill never plays faster than real time (%.2f x)" % kc._kill_rate)
		_ok(absf(kc._real_for() - Killcam.play_length()) < 0.2,
			"and even a short buffer fills play_length() (%.2f s of %.2f)" % [kc._real_for(), Killcam.play_length()])
		# A long enough clip keeps the old rate.
		kc._clip = c2
		kc._t_kill = float(c2.t_kill)
		kc._t_end = minf(float(c2.t_kill) + Killcam.POST, float((c2.frames as Array)[(c2.frames as Array).size() - 1][0]))
		kc._plan_playback(1, 2)
		_ok(is_equal_approx(kc._kill_rate, Killcam.SLOW), "a long clip keeps the old SLOW (%.2f x)" % kc._kill_rate)

		# 11) A long chain (9 s of wallrun) must not be cut off before the kill: the server unlocks after
		# play_length(), so the planner compresses the run-up instead. The kill is always inside the
		# replay, and the last RUNUP_KEEP seconds still run at their own speed.
		var c6 := _clip(2.0, 9.0)
		kc._clip = c6
		kc._t_kill = float(c6.t_kill)
		kc._t_end = minf(float(c6.t_kill) + Killcam.POST, float((c6.frames as Array)[(c6.frames as Array).size() - 1][0]))
		kc._plan_playback(1, 2)
		_ok(kc._runup > 1.0, "a long chain compresses its run-up (%.2f x)" % kc._runup)
		_ok(kc._pt <= float(c6.t_kill) - Killcam.MIN_LEN, "the replay still starts before the kill (%.2f s in)" % (float(c6.t_kill) - kc._pt))
		_ok(kc._t_end >= float(c6.t_kill), "the kill is inside the replay")
		_ok(absf(kc._real_for() - Killcam.play_length()) < 0.2,
			"and the whole replay fills play_length() (%.2f s of %.2f)" % [kc._real_for(), Killcam.play_length()])
		# The run-up rate is capped: even a pathological clip never crawls.
		_ok(kc._runup <= Killcam.MAX_RUNUP, "the run-up compression is capped (%.2f x)" % kc._runup)
		kc._clip = {}
		kc._frames = []
		kc._events = []
		kc._clock = 0.0

	print("KILLCAM DIRECTOR CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
