extends Node
## The grapple (shared/grapple.gd + Player): headless, on test geometry far above any map.
## Covers the anchor ray (hit, miss past RANGE), the pull maths (toward the anchor, capped at PULL_SPEED,
## sideways bleed), the press/cooldown rules, every way a pull ends, a real pawn pulled across a gap
## that keeps its speed when it lets go, the synced state (move_fx, grappling, grapple_at), the style
## side (GRAPPLE KILL, the combo move, the speed meter chip) and the binding.
##   godot --headless --path . res://tools/check_grapple.tscn   → "GRAPPLE CHECK OK"
var fails := 0
var failed: Array[String] = []
const BASE := Vector3(0, 300, 0)


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1
		failed.append(msg)


func _box(center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	s.shape = sh
	b.add_child(s)
	add_child(b)
	b.global_position = center


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	_box(BASE + Vector3(0, -0.5, 0), Vector3(30, 1, 30)) # start floor
	_box(BASE + Vector3(0, 4, -26), Vector3(30, 10, 1)) # target wall: face at z = -25.5, 25.5 m away
	_box(BASE + Vector3(0, -0.5, -21), Vector3(30, 1, 8)) # landing ledge under the wall
	_box(BASE + Vector3(11, 0.7, -6), Vector3(6, 1.4, 0.5)) # off the pawn's lane: a 1.4 m wall the eye sees over, the chest does not
	await _frames(3)
	_maths()
	await _anchor()
	_rules()
	await _pawn()
	_style()
	_done()


func _maths() -> void:
	var at := BASE + Vector3(0, 1, -20)
	var chest := BASE + Vector3(0, 1, 0)
	var v := Grapple.pull(Vector3.ZERO, chest, at, 1.0 / 60.0)
	_ok(v.normalized().dot(Vector3.FORWARD) > 0.99, "the pull points at the anchor")
	_ok(is_equal_approx(v.length(), Grapple.PULL_ACCEL / 60.0), "one tick adds PULL_ACCEL·dt (%.2f m/s)" % v.length())
	v = Vector3.FORWARD * 30.0
	_ok(is_equal_approx(Grapple.pull(v, chest, at, 1.0 / 60.0).length(), 30.0), "already faster than PULL_SPEED: the pull adds nothing, takes nothing")
	v = Vector3.ZERO
	for i in 120:
		v = Grapple.pull(v, chest, at, 1.0 / 60.0)
	_ok(is_equal_approx(v.length(), Grapple.PULL_SPEED), "the pull tops out at PULL_SPEED (%.1f m/s)" % v.length())
	var side := Grapple.pull(Vector3.RIGHT * 10.0, chest, at, 0.5)
	_ok(absf(side.x) < 10.0 * exp(-Grapple.SIDE_DAMP * 0.5) + 0.01, "sideways speed bleeds off (%.2f m/s left of 10)" % side.x)
	_ok(Grapple.PULL_ACCEL > 9.8 * 3.0, "the pull beats gravity by a wide margin, upward too")


func _anchor() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var ex: Array[RID] = []
	var eye := BASE + Vector3(0, 1.6, 0)
	var hit := Grapple.find_anchor(space, eye, Vector3.FORWARD, ex)
	_ok(not hit.is_empty() and absf((hit.point as Vector3).z - (BASE.z - 25.5)) < 0.05, "a wall in range is an anchor (z %.2f)" % (hit.get("point", Vector3.ZERO) as Vector3).z)
	_ok(Grapple.find_anchor(space, eye, Vector3.BACK, ex).is_empty(), "nothing within RANGE: a miss")
	var side := BASE + Vector3(11, 0, 0)
	var low := Grapple.find_anchor(space, side + Vector3.UP * 1.6, Vector3.FORWARD, ex)
	var g0 := Grapple.new()
	g0.begin(low.get("point", Vector3.ZERO))
	g0.t = 0.5
	_ok(not low.is_empty() and not g0.should_end(side, true, space, ex), "a low wall the eye saw over does not cut the rope")
	_ok(Grapple.find_anchor(space, eye, Vector3.ZERO, ex).is_empty(), "no aim: no anchor")
	var g := Grapple.new()
	_ok(not g.try_start(space, eye, Vector3.BACK, ex) and is_equal_approx(g.cd, Grapple.MISS_COOLDOWN), "a miss costs only MISS_COOLDOWN")
	g.cd = 0.0
	_ok(g.try_start(space, eye, Vector3.FORWARD, ex) and g.active and is_equal_approx(g.cd, Grapple.COOLDOWN), "a hit anchors and starts the COOLDOWN")
	g.release()
	_ok(not g.try_start(space, eye, Vector3.FORWARD, ex), "no second pull inside the cooldown")
	g.tick_cooldown(Grapple.COOLDOWN)
	_ok(g.try_start(space, eye, Vector3.FORWARD, ex), "after the cooldown it fires again")
	await _frames(1)


func _rules() -> void:
	var space := get_viewport().world_3d.direct_space_state
	var ex: Array[RID] = []
	var g := Grapple.new()
	var at := BASE + Vector3(0, 2, -25.5)
	g.begin(at)
	var feet := BASE
	_ok(not g.should_end(feet, true, space, ex), "held, in reach, line clear: keep pulling")
	_ok(g.should_end(feet, false, space, ex), "letting go ends it")
	_ok(g.should_end(at + Vector3(0, -Grapple.CHEST, 1.0), true, space, ex), "arriving ends it")
	g.t = Grapple.PULL_TIME
	_ok(g.should_end(feet, true, space, ex), "PULL_TIME ends it")
	g.t = 0.0
	var under := BASE + Vector3(0, -4, 0)
	_ok(not g.should_end(under, true, space, ex), "the first CUT_GRACE of a pull is never cut")
	g.t = Grapple.CUT_GRACE
	_ok(g.should_end(under, true, space, ex), "after it, a floor between body and anchor cuts the rope")


## A real pawn on the start floor: press, hold, fly over the gap toward the wall, let go, keep the speed.
func _pawn() -> void:
	Game.is_offline = true
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = 1
	p.position = BASE + Vector3(0, 0.1, 6)
	p.set_physics_process(false)
	add_child(p)
	await _frames(4)
	for i in 6:
		p.move_and_slide()
	_ok(InputMap.has_action("grapple") and not InputMap.action_get_events("grapple").is_empty(), "grapple has a default binding")
	var listed := false
	for a in Game.REBIND_ACTIONS:
		if a[0] == "grapple":
			listed = true
	_ok(listed, "grapple can be rebound in Settings")
	var at := BASE + Vector3(0, 3, -25.5)
	p.start_grapple(at, true) # standing on the start floor (no gravity tick has run to make is_on_floor true)
	_ok(p.velocity.y >= Grapple.GROUND_LIFT - 0.01, "a pull from the floor lifts off it")
	Input.action_press("grapple")
	var dt := 1.0 / 60.0
	var top := 0.0
	var fx_seen := false
	var synced := false
	var ticks := 0
	while p.is_grappling() and ticks < 200:
		p.velocity.y += float(p.get_gravity().y) * dt * Movement.gravity_scale(p)
		p._apply_grapple_pull(dt)
		p._tick_move_fx(dt)
		fx_seen = fx_seen or p.move_fx == Player.MOVE_GRAPPLE
		synced = synced or (p.grappling and p.grapple_at.is_equal_approx(at))
		top = maxf(top, p.velocity.length())
		p.move_and_slide()
		ticks += 1
	Input.action_release("grapple")
	_ok(ticks < 200 and p.global_position.distance_to(at) < 4.0, "the pull crosses the gap to the wall (%.1f m from the anchor after %d ticks)" % [p.global_position.distance_to(at), ticks])
	_ok(top >= Grapple.PULL_SPEED * 0.9, "and gets up to speed (%.1f m/s)" % top)
	_ok(fx_seen, "move_fx is MOVE_GRAPPLE while pulling")
	_ok(synced, "grappling / grapple_at carry the rope for other clients")
	# Let go halfway: the speed is the player's to keep.
	p.position = BASE + Vector3(0, 0.1, 6)
	p.velocity = Vector3.ZERO
	p._grapple.reset()
	await _frames(1)
	p.move_and_slide()
	p.start_grapple(at, true)
	Input.action_press("grapple")
	for i in 25:
		p.velocity.y += float(p.get_gravity().y) * dt * Movement.gravity_scale(p)
		p._apply_grapple_pull(dt)
		p.move_and_slide()
	var before := p.velocity.length()
	Input.action_release("grapple")
	p._apply_grapple_pull(dt)
	_ok(not p.is_grappling(), "letting go of the key ends the pull")
	_ok(is_equal_approx(p.velocity.length(), before), "and keeps every m/s it built (%.1f m/s)" % p.velocity.length())
	_ok(not p.grappling, "the synced flag drops with it")
	# Dying cuts the rope.
	p.start_grapple(at)
	p._die()
	_ok(not p.is_grappling() and not p.grappling, "dying cuts the rope")
	p.queue_free()


func _style() -> void:
	var t := Style.detect({"weapon": &"rifle", "grapple": true})
	_ok(t.has(Style.GRAPPLE), "a gun kill on the rope is a GRAPPLE KILL")
	_ok(not Style.detect({"weapon": &"rifle", "grapple": true, "shooter_air": 2.0}).has(Style.AIRSHOT), "and not also an AIRSHOT (the rope is the move)")
	_ok(Style.ORDER.has(Style.GRAPPLE) and Style.LABELS.has(Style.GRAPPLE) and Style.POINTS.has(Style.GRAPPLE), "GRAPPLE KILL has points, a label and a place in the order")
	_ok(Combo.POINTS.has(Combo.GRAPPLE) and Combo.LABELS.has(Combo.GRAPPLE), "a pull is a combo move")
	_ok(SpeedMeter.state_name(false, false, false, false, true) == "GRAPPLE", "the speed meter names the pull")
	_ok(SpeedMeter.state_name(true, false, false, false, true) == "WALLRUN", "and a wallrun outranks it")


func _done() -> void:
	print("GRAPPLE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in failed:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
