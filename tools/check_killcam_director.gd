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
	frames.append(_frame(t_kill + 1.0 / Killcam.RATE, Vector3(0.0, 0.0, z + 0.05)))
	frames.append(_frame(t_kill + 2.0 / Killcam.RATE, Vector3(0.0, 0.0, z + 0.1)))
	var events: Array = [[t_kill, "death", 2, 1, "rifle", true]]
	return {"t_kill": t_kill, "chain_start": chain_start, "frames": frames, "events": events, "meta": {}}


func _ready() -> void:
	# 1) The clip starts at the chain, not PRE seconds before the kill.
	var c := _clip(6.0, 1.2)
	var start := Killcam.action_start(c.frames, c.events, float(c.t_kill), 1)
	_ok(start <= float(c.chain_start) + 0.05 and start >= float(c.chain_start) - Killcam.LEAD_IN - 0.05,
		"starts at the wallrun chain (%.2f s, chain at %.2f)" % [start, float(c.chain_start)])
	_ok(start > float(c.t_kill) - Killcam.PRE, "and later than the old fixed PRE window (%.2f s in)" % (float(c.t_kill) - start))

	# 2) A chain longer than PRE is not cut off at PRE: you get the whole run.
	var c2 := _clip(2.0, 7.0)
	var start2 := Killcam.action_start(c2.frames, c2.events, float(c2.t_kill), 1)
	_ok(start2 < float(c2.t_kill) - Killcam.PRE, "a long chain is not cut off at PRE (%.2f s in)" % (float(c2.t_kill) - start2))
	_ok(start2 >= float(c2.t_kill) - Killcam.LOOKBACK, "and stays inside the lookback")
	_ok(start2 <= float(c2.chain_start) + 0.05, "starting at the chain (%.2f s, chain at %.2f)" % [start2, float(c2.chain_start)])

	# 3) Nothing happened: a short clip instead of a long dull one.
	var c3 := _clip(6.0, 0.0)
	c3.frames.pop_back()
	c3.frames.pop_back()
	var start3 := Killcam.action_start(c3.frames, [], float(c3.t_kill), 1)
	_ok(is_equal_approx(start3, float(c3.t_kill) - Killcam.MIN_LEN), "a dull kill is cut to MIN_LEN (%.2f s)" % (float(c3.t_kill) - start3))

	# 4) Speed profile: fast over the walk, 1x on the chain, slow around the kill.
	var runs := Killcam.dull_runs(c.frames, c.events, 1)
	_ok(Killcam.rate_at(2.0, float(c.t_kill), runs) == Killcam.FAST, "the walk is fast-forwarded")
	_ok(Killcam.rate_at(float(c.chain_start) + 0.4, float(c.t_kill), runs) == 1.0, "the wallrun runs at normal speed")
	_ok(Killcam.rate_at(float(c.t_kill), float(c.t_kill), runs) == Killcam.SLOW, "the kill is slow motion")
	_ok(Killcam.rate_at(float(c.t_kill) + Killcam.SLOW_TO + 0.2, float(c.t_kill), runs) == 1.0,
		"the tail after the kill is normal speed")

	# 5) Short dull gaps are not worth compressing (no flickering between 1x and 2.5x).
	var short_gap: Array = [_frame(0.0, Vector3.ZERO), _frame(1.0 / Killcam.RATE, Vector3(0.0, 0.0, 0.05), Player.MOVE_WALLRUN),
		_frame(2.0 / Killcam.RATE, Vector3(0.0, 0.0, 0.1))]
	_ok(Killcam.dull_runs(short_gap, [], 1).is_empty(), "a gap shorter than FOLD_MIN (%.2f s) is not compressed" % Killcam.FOLD_MIN)

	# 6) The VHS fast-forward overlay is on exactly where the replay is compressed, and never on the kill.
	_ok(Killcam.vhs_amount(2.0, float(c.t_kill), runs) > 0.9, "the VHS overlay is on over the walk")
	_ok(is_equal_approx(Killcam.vhs_amount(float(c.chain_start) + 0.4, float(c.t_kill), runs), 0.0),
		"and off on the wallrun")
	_ok(is_equal_approx(Killcam.vhs_amount(float(c.t_kill), float(c.t_kill), runs), 0.0),
		"and off in the slow-motion kill")

	# 7) The combo payout climbs and lands exactly on the kill.
	var bank := 400
	var t0 := 10.0
	var tk := 14.0
	_ok(Killcam.ticker_value(bank, t0, t0, tk) == 0, "the payout starts at 0")
	_ok(Killcam.ticker_value(bank, tk, t0, tk) == bank, "and lands on the full bank at the kill")
	var half := Killcam.ticker_value(bank, 12.0, t0, tk)
	_ok(half > 0 and half < bank, "with a value in between halfway (%d)" % half)
	_ok(Killcam.ticker_value(bank, tk + 5.0, t0, tk) == bank, "and never overshoots")
	_ok(Killcam.ticker_value(0, 12.0, t0, tk) == 0, "no bank, no counter")

	print("KILLCAM DIRECTOR CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
