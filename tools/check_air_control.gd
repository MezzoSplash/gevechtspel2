extends Node
## #152 air control: Movement.air_steer turns the air velocity toward the held direction, slowly,
## without adding speed, and ignores a wish pointing backwards. Headless:
##   godot --headless --path . res://tools/check_air_control.tscn

var fails := 0


func _ok(c: bool, msg: String) -> void:
	print(("  PASS " if c else "  FAIL ") + msg)
	if not c:
		fails += 1


func _ready() -> void:
	var dt := 1.0 / 60.0
	var vel := Vector3(0, 0, -10) # flying forward at 10 m/s
	var right := Vector3(1, 0, 0)
	var v := vel
	for i in 60: # hold D for one second
		v = Movement.air_steer(v, right, dt)
	var turned := absf(vel.angle_to(v))
	_ok(is_equal_approx(v.length(), vel.length()), "speed kept (%.3f)" % v.length())
	_ok(turned > 0.5 and turned <= Player.AIR_STEER_RATE + 0.01, "1 s of D turns %.0f deg (max %.0f)" % [rad_to_deg(turned), rad_to_deg(Player.AIR_STEER_RATE)])
	_ok(v.x > 0.0, "turns toward the held side")
	_ok(Movement.air_steer(vel, Vector3(0, 0, 1), dt) == vel, "holding back does nothing")
	_ok(Movement.air_steer(vel, Vector3.ZERO, dt) == vel, "no input does nothing")
	var near := Movement.air_steer(vel, Vector3(0.001, 0, -1).normalized(), dt)
	_ok(near.angle_to(Vector3(0.001, 0, -1)) < 0.0001, "never overshoots the wish direction")
	print("AIR CONTROL CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
