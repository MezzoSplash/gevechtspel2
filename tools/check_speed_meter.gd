extends Node
## SpeedMeter (HUD speed readout): the speed maths and the state names, headless, no match.
##   godot --headless res://tools/check_speed_meter.tscn   → "SPEED METER CHECK OK"
var fails := 0
var failed: Array[String] = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1
		failed.append(msg)


func _pawn() -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	return p


func _ready() -> void:
	_ok(is_equal_approx(SpeedMeter.flat_speed(Vector3(3, 50, 4)), 5.0), "flat speed ignores the vertical part")
	_ok(is_equal_approx(SpeedMeter.fill_of(0.0), 0.0) and is_equal_approx(SpeedMeter.fill_of(SpeedMeter.MAX_SPEED), 1.0), "bar is empty at 0 and full at MAX_SPEED")
	_ok(is_equal_approx(SpeedMeter.fill_of(1000.0), 1.0) and is_equal_approx(SpeedMeter.fill_of(-5.0), 0.0), "bar is clamped to 0..1")
	_ok(SpeedMeter.SPRINT_MARK < SpeedMeter.MAX_SPEED and is_equal_approx(SpeedMeter.SPRINT_MARK, Player.SPRINT_SPEED), "the tick on the bar is the sprint speed")
	_ok(SpeedMeter.state_of(null) == "", "no pawn: no state")

	var p := _pawn()
	_ok(SpeedMeter.state_of(p) == "", "standing still: no state")
	p._sliding = true
	_ok(SpeedMeter.state_of(p) == "SLIDE", "sliding is named SLIDE")
	p._diving = true
	_ok(SpeedMeter.state_of(p) == "DIVE", "a dive beats a slide")
	p._wallrunning = true
	_ok(SpeedMeter.state_of(p) == "WALLRUN", "a wallrun beats a dive")
	p._wallrunning = false
	p._diving = false
	p._sliding = false
	p._surf_t = 0.3
	_ok(SpeedMeter.state_of(p) == "SURF" or p.is_on_floor(), "surf contact in the air is named SURF")

	var m := SpeedMeter.new()
	add_child(m)
	m.update_from(Vector3(6, 0, 8), "WALLRUN")
	_ok(m._num.text == "10" and m._state.text == "WALLRUN", "the labels follow the pawn (10 m/s, WALLRUN)")
	m.update_from(Vector3.ZERO, "")
	_ok(m._num.text == "0" and m._state.text == "", "standing still reads 0 and no state")

	print("SPEED METER CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for f in failed:
		print("FAILED: %s" % f)
	get_tree().quit(1 if fails > 0 else 0)
