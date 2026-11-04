extends Node
## Floaty movement pass headless: apex hang time scales gravity only near the top of a jump (not on
## wall runs), the dive boost fades smoothly to its kept part and never below sprint speed, and the
## dive/slide cooldowns block spam.
##   godot --headless --path . res://tools/check_floaty.tscn   → "FLOATY CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.set_physics_process(false)
	add_child(p)
	p.velocity = Vector3(0, 1.0, 0)
	_ok(is_equal_approx(Movement.gravity_scale(p), Player.APEX_GRAVITY_SCALE), "apex: lighter gravity")
	p.velocity.y = 6.0
	_ok(Movement.gravity_scale(p) == 1.0, "rising fast: full gravity")
	p.velocity.y = 0.5
	p._wallrunning = true
	_ok(Movement.gravity_scale(p) == 1.0, "wall run: own sink, no hang time")
	p._wallrunning = false
	p.velocity = Vector3(0, 0, -Player.SPRINT_SPEED)
	Movement.start_dive(p, false)
	var start := Vector2(p.velocity.x, p.velocity.z).length()
	_ok(is_equal_approx(start, Player.SPRINT_SPEED + Player.DIVE_BOOST), "dive adds DIVE_BOOST (%.2f)" % start)
	var prev := start
	var smooth := true
	for i in 60:
		Movement.tick_boosts(p, 1.0 / 60.0)
		var sp := Vector2(p.velocity.x, p.velocity.z).length()
		smooth = smooth and prev - sp < 0.15 and sp <= prev + 1e-4
		prev = sp
	var kept := Player.SPRINT_SPEED + Player.DIVE_BOOST * (1.0 - Player.DIVE_BOOST_FADE)
	_ok(smooth, "boost fades smoothly (no hard cut)")
	_ok(absf(prev - kept) < 0.1, "after 1 s the kept boost remains (%.2f, want %.2f)" % [prev, kept])
	p._dive_cd = Player.DIVE_COOLDOWN
	p._diving = false
	p._dive_used = false
	Movement.try_air_dive(p, false, false)
	_ok(not p._diving, "dive cooldown blocks a new dive")
	p._slide_cd = Player.SLIDE_COOLDOWN
	Movement.try_start_slide(p, true, false)
	_ok(not p._sliding, "slide cooldown blocks a new slide")
	Movement.tick_boosts(p, 1.0)
	_ok(p._dive_cd == 0.0 and p._slide_cd == 0.0, "cooldowns run out")
	print("FLOATY CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
