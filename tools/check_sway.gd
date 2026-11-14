extends Node
## #255. The viewmodel spring must not run away when a frame is long, and a 60 fps step
## must stay the old one-step spring (same constants, same result when nothing hits the new clamps).
##   ./run.sh --headless res://tools/check_sway.tscn   → "SWAY CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	Game.view_sway = 2
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = 1
	p.position = Vector3(0, 3, 0)
	add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	var w := p.weapon
	w.set_process(false)
	_long_frames(p, w)
	_matches_60(p, w)
	print("SWAY CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Twenty half-second frames, including one that starts from a blown-out spring. The gun stays put.
func _long_frames(p: Player, w: Weapon) -> void:
	_reset(w)
	var worst_p := 0.0
	var worst_r := 0.0
	for i in 20:
		p.rotation.y += 0.8
		p.head.rotation.x = sin(float(i) * 0.7) * 0.5
		if i == 3:
			w._sway_v = Vector3(40.0, -40.0, 40.0)
		w._tick_sway(0.5)
		worst_p = maxf(worst_p, w._sway_p.length())
		worst_r = maxf(worst_r, w._sway_rot.length())
	_ok(worst_p <= 0.09, "half-second frames keep the sway inside 0.09 m (peak %.4f)" % worst_p)
	_ok(worst_r <= 0.2, "half-second frames keep the tilt inside 0.2 rad (peak %.4f)" % worst_r)


## One step of the pre-fix spring, y clamp included, x/z left alone. At 1/60 s that is what we still do.
func _matches_60(p: Player, w: Weapon) -> void:
	_reset(w)
	var dt := 1.0 / 60.0
	p.rotation.y = 0.2
	p.head.rotation.x = -0.1
	w._tick_sway(dt) # init frame: rate is zero, both sides start from rest
	var sp := w._sway_p
	var sv := w._sway_v
	var drifted := false
	for i in 45:
		var prev_yaw := p.rotation.y
		var prev_pitch := p.head.rotation.x
		p.rotation.y += 0.2
		p.head.rotation.x = sin(float(i) * 0.35) * 0.4
		w._tick_sway(dt)
		var yaw_rate := clampf(wrapf(p.rotation.y - prev_yaw, -PI, PI) / dt, -25.0, 25.0)
		var pitch_rate := clampf((p.head.rotation.x - prev_pitch) / dt, -25.0, 25.0)
		var target := Vector3(yaw_rate * Weapon.SWAY_LOOK, -pitch_rate * Weapon.SWAY_LOOK, 0.0)
		target.x = clampf(target.x, -Weapon.SWAY_MAX, Weapon.SWAY_MAX)
		target.y = clampf(target.y, -Weapon.SWAY_MAX, Weapon.SWAY_MAX)
		sv += ((target - sp) * Weapon.SWAY_SPRING - sv * Weapon.SWAY_DAMP) * dt
		sp += sv * dt
		sp.y = clampf(sp.y, -0.09, 0.05)
		if not (w._sway_p.is_equal_approx(sp) and w._sway_v.is_equal_approx(sv)):
			drifted = true
			break
	_ok(not drifted, "a 60 fps step matches the old one-step spring")
	_ok(sp.length() < 0.09, "that 60 fps run never reaches the new x/z clamps (%.4f m)" % sp.length())


func _reset(w: Weapon) -> void:
	w._sway_p = Vector3.ZERO
	w._sway_v = Vector3.ZERO
	w._sway_rot = Vector3.ZERO
	w._sway_init = false
	w._sway_fall = 0.0
