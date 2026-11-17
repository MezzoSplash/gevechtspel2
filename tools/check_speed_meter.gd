extends Node
## Speed meter (crystal restyle step 4): the pure helpers, the seam easing, and that the meter is
## a row of the HUD's bottom stack right above HP, hidden without a live local pawn.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	_check_helpers()
	_check_easing()
	await _check_hud()
	print("SPEED METER CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _check_helpers() -> void:
	print("-- helpers")
	_ok(is_equal_approx(SpeedMeter.flat_speed(Vector3(3, -20, 4)), 5.0), "flat_speed ignores the fall")
	_ok(SpeedMeter.fill_of(0.0) == 0.0, "standing still lights nothing")
	_ok(SpeedMeter.fill_of(-3.0) == 0.0, "fill clamps below 0")
	_ok(is_equal_approx(SpeedMeter.fill_of(SpeedMeter.FULL_SPEED * 0.5), 0.5), "half speed lights half the seam")
	_ok(SpeedMeter.fill_of(SpeedMeter.FULL_SPEED * 3.0) == 1.0, "fill clamps at 1")
	_ok(SpeedMeter.fill_of(Player.SPRINT_SPEED) < SpeedMeter.fill_of(Player.CARRY_MAX), "carry lights more than sprint")
	_ok(SpeedMeter.fill_of(Player.CARRY_MAX) < 1.0, "a carry does not max the seam, a surf can still climb")
	_ok(SpeedMeter.state_name(false, false, false, false) == "", "running has no state")
	_ok(SpeedMeter.state_name(true, true, true, true) == "WALLRUN", "wallrun wins over everything")
	_ok(SpeedMeter.state_name(false, true, true, true) == "DIVE", "dive wins over slide and surf")
	_ok(SpeedMeter.state_name(false, false, true, true) == "SLIDE", "slide wins over surf")
	_ok(SpeedMeter.state_name(false, false, false, true) == "SURF", "surf on its own")
	_ok(SpeedMeter.state_of(null) == "", "no pawn, no state")


func _check_easing() -> void:
	print("-- seam easing")
	var m := SpeedMeter.new()
	add_child(m)
	m.show_speed(SpeedMeter.FULL_SPEED, "SURF", 1.0 / 60.0)
	_ok(m.lit() > 0.0 and m.lit() < 1.0, "one frame moves the seam part of the way (%.3f)" % m.lit())
	_ok(m.speed == SpeedMeter.FULL_SPEED and m.state == "SURF", "number and state are not smoothed")
	# Frame-rate independent: 60 frames of 1/60 s land where one... several bigger steps land.
	var a := SpeedMeter.new()
	var b := SpeedMeter.new()
	add_child(a)
	add_child(b)
	for i in 60:
		a.show_speed(12.0, "", 1.0 / 60.0)
	for i in 15:
		b.show_speed(12.0, "", 1.0 / 15.0)
	_ok(absf(a.lit() - b.lit()) < 0.002, "easing is the same at 60 and 15 fps (%.4f / %.4f)" % [a.lit(), b.lit()])
	_ok(absf(a.lit() - SpeedMeter.fill_of(12.0)) < 0.01, "a second of the same speed settles on it")
	for n in [m, a, b]:
		n.queue_free()


func _check_hud() -> void:
	print("-- in the HUD")
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	add_child(root)
	var hud: Hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var m := hud.get_node_or_null("Bottom/Speed") as SpeedMeter
	_ok(m != null and m == hud.speed_meter, "the meter is Bottom/Speed")
	if m == null:
		return
	var hp_row := hud.get_node("Bottom/HpRow") as Control
	_ok(m.get_index() == hp_row.get_index() - 1, "it sits right above the HP row")
	hud._player = null
	await get_tree().process_frame
	_ok(not m.visible, "hidden without a local pawn")
	root.queue_free()
	await get_tree().process_frame
