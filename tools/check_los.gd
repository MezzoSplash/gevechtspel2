extends Node
## LOS scorestreak. Headless:
##   ./run.sh --headless res://tools/check_los.tscn   → "LOS CHECK OK"
## 5 kills bank the RC-XD and not LOS. 7 banks LOS. The body keeps its speed, one bash from the
## hands kills and the gun stays quiet, and a landed bash snaps the body to the hands and ends the
## streak (a whiff does not). Killing the body ends it. The trick needs the body's speed, not the
## hands being airborne. After 5 s the camera is back on the body.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _h(p: Player) -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	_ok(Game.NET_VERSION == "0.5.14", "NET_VERSION is 0.5.14")
	_charges()
	_style_rules()
	var floor := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	col.shape = box
	floor.add_child(col)
	floor.position = Vector3(0, -0.5, 0)
	add_child(floor)
	var p := _pawn(1, false)
	p.position = Vector3(0, 0.05, 0)
	var bot := _pawn(-3, true)
	bot.position = Vector3(30, 0.05, 30)
	for _i in 4:
		await get_tree().physics_frame
	p._spawn_protect = 0.0
	bot._spawn_protect = 0.0
	bot._bot_brain = null
	await _gun_fires(p)
	await _activate(p, bot)
	print("LOS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _charges() -> void:
	Game.streak_progress.clear()
	Game.streak_charges.clear()
	Game.streak_earned.clear()
	for _i in 5:
		Game._bump_streak(1, 99)
	var bits := int(Game.streak_charges.get(1, 0))
	_ok((bits & Game.CHARGE_RCXD) != 0 and (bits & Game.CHARGE_LOS) == 0, "5 kills: RC-XD charged, LOS not")
	for _i in 2:
		Game._bump_streak(1, 99)
	bits = int(Game.streak_charges.get(1, 0))
	_ok((bits & Game.CHARGE_LOS) != 0 and int(Game.streak_progress.get(1, 0)) == 7, "7 kills: LOS charged")
	Game._bump_streak(1, 99)
	_ok(int(Game.streak_progress.get(1, 0)) == 7, "the counter stops at 7")
	for _i in 7:
		Game._bump_streak(-4, 98)
	_ok((int(Game.streak_charges.get(-4, 0)) & Game.CHARGE_LOS) == 0, "a bot does not bank LOS")


func _style_rules() -> void:
	_ok(int(Style.POINTS[Style.LOS]) == 175, "LOS is 175 style")
	_ok(int(Style.POINTS[Style.LOS_LONG]) == 350, "LOS LONG is 350 style")
	var fast := Style.detect({"weapon": &"melee", "los": true, "body_speed": 13.0})
	_ok(fast.has(Style.LOS), "melee + LOS + 13 m/s on the body counts")
	var near := Style.detect({"weapon": &"melee", "los": true, "body_speed": 13.0, "los_dist": 8.0})
	_ok(near.has(Style.LOS) and not near.has(Style.LOS_LONG), "an 8 m snap stays LOS")
	var far := Style.detect({"weapon": &"melee", "los": true, "body_speed": 13.0, "los_dist": 30.0})
	_ok(far.has(Style.LOS_LONG) and not far.has(Style.LOS), "a 30 m snap is LOS LONG, not LOS")
	var slow := Style.detect({"weapon": &"melee", "los": true, "body_speed": 5.0, "shooter_air": 2.0})
	_ok(not slow.has(Style.LOS) and not slow.has(Style.LOS_LONG), "a slow body does not get LOS just because the hands are up")
	var plain := Style.detect({"weapon": &"melee", "los": false, "body_speed": 18.0})
	_ok(not plain.has(Style.LOS), "a fast bash without the streak is not LOS")


func _pawn(id: int, bot: bool) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = id
	p.is_bot = bot
	p.name = ("bot%d" % -id) if bot else str(id)
	add_child(p)
	return p


func _gun_fires(p: Player) -> void:
	if p.weapon == null or p.weapon.def == null or p.weapon.ammo <= 0:
		_ok(false, "pawn has a loaded gun")
		return
	_ok(not p.weapon.trigger_locked(), "the trigger is open before LOS")
	# Headless has no captured mouse, so a click never reaches _try_fire here. The lock above is
	# the same check the gun uses. When a window can capture the mouse, one shot must spend ammo.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var before := p.weapon.ammo
		Input.action_press("fire")
		await get_tree().physics_frame
		Input.action_release("fire")
		_ok(p.weapon.ammo < before, "the gun fires when LOS is off (%d -> %d)" % [before, p.weapon.ammo])
	for _i in 8:
		await get_tree().physics_frame


func _activate(p: Player, bot: Player) -> void:
	p.is_dead = true
	Game.try_activate_streak(1, 2)
	_ok((int(Game.streak_charges.get(1, 0)) & Game.CHARGE_LOS) != 0, "a dead pawn keeps the charge")
	p.is_dead = false
	Game.streak_charges[-3] = Game.CHARGE_LOS
	Game.try_activate_streak(-3, 2)
	_ok((int(Game.streak_charges.get(-3, 0)) & Game.CHARGE_LOS) != 0 and LosHands.for_owner(-3) == null,
		"a bot does not spend LOS")
	p.velocity = Vector3(14.0, 0.0, 0.0)
	var before := _h(p)
	Game.try_activate_streak(1, 2)
	_ok(LosHands.for_owner(1) != null and Game.los_view and p.los_coast, "activate puts the hands out")
	_ok((int(Game.streak_charges.get(1, 0)) & Game.CHARGE_LOS) == 0, "activate spends the charge")
	for _i in 30:
		await get_tree().physics_frame
	var after := _h(p)
	_ok(after > 8.0, "body still fast after 0.5 s (%.1f -> %.1f)" % [before, after])
	LosHands.abort_for(1)
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(0, 0.05, 0)
	p.rotation = Vector3.ZERO
	await get_tree().physics_frame
	p.velocity = Vector3.ZERO
	var origin := p.global_position
	_ok(LosHands.launch(p), "launch from a standstill")
	var hands := LosHands.for_owner(1)
	_ok(hands != null and hands.collision_layer == 0, "hands exist and are not a target")
	for _i in 20:
		await get_tree().physics_frame
	var moved := Vector2(p.global_position.x - origin.x, p.global_position.z - origin.z).length()
	_ok(moved < 0.35 and LosHands.for_owner(1) != null, "from rest the body stays (%.2f m) and the hands stay out" % moved)
	hands = LosHands.for_owner(1)
	hands._pitch = 1.0
	hands._pose_cam()
	var climb_y := hands.global_position.y
	var body_y := p.global_position.y
	Input.action_press("move_forward")
	for _i in 20:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_ok(hands.velocity.y > 4.0, "looking up and holding W climbs (vy %.1f)" % hands.velocity.y)
	_ok(hands.global_position.y > climb_y + 0.4, "the hands gained height")
	_ok(absf(p.global_position.y - body_y) < 0.35, "the body stays on its line while the hands climb")
	# A whiff has to keep the hands out: only a landed bash is the payoff.
	hands._swing_cd = 0.0
	p.weapon._melee_cd = 0.0
	hands._request_swing()
	_ok(LosHands.for_owner(1) != null, "a missed bash keeps the hands out")
	_ok(p.weapon.trigger_locked(), "LOS locks the trigger")
	var ammo := p.weapon.ammo
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("fire")
	for _i in 6:
		await get_tree().physics_frame
	Input.action_release("fire")
	_ok(p.weapon.ammo == ammo, "the gun does not fire during LOS (%d -> %d)" % [ammo, p.weapon.ammo])
	# The style trick needs the body's speed, not the hands being out.
	p.velocity = Vector3(13.0, 0.0, 0.0)
	p._obs_speed = 0.0
	Game._shot_ctx = {"shooter": p, "origin": hands.global_position, "scoped": false, "burst": {}}
	var tagged := Tricks.detect(Game, 1, -3, &"melee", false)
	_ok(tagged.has(Style.LOS), "trick uses body velocity, not the smoothed speed")
	p.velocity = Vector3(5.0, 0.0, 0.0)
	tagged = Tricks.detect(Game, 1, -3, &"melee", false)
	_ok(not tagged.has(Style.LOS), "5 m/s on the body is not LOS")
	# The trick reads how far the hands were from the body at the swing (LosHands.snap_m).
	p.velocity = Vector3(13.0, 0.0, 0.0)
	hands.snap_m = 30.0
	tagged = Tricks.detect(Game, 1, -3, &"melee", false)
	_ok(tagged.has(Style.LOS_LONG) and not tagged.has(Style.LOS), "a 30 m snap reads LOS LONG through Tricks")
	hands.snap_m = 0.0
	Game._shot_ctx = {}
	p.velocity = Vector3.ZERO
	# The payoff: one bash kills, and the body snaps to the hands and the streak ends there.
	var eye := p.head.global_position.y - p.global_position.y
	var feet := Vector3(6.0, 1.7, 6.0)
	hands.global_position = feet + Vector3.UP * LosHands.EYE_H
	hands.velocity = Vector3.ZERO
	hands._pitch = 0.0 # the climb test pitched the camera up; a level bash needs a level look
	hands._pose_cam()
	var flat := Vector3(hands.look.x, 0.0, hands.look.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(0, 0, -1)
	flat = flat.normalized()
	bot.global_position = feet + flat * 1.35
	bot.velocity = Vector3.ZERO
	bot.hp = Player.MAX_HP
	bot.is_dead = false
	bot._spawn_protect = 0.0
	hands._swing_cd = 0.0
	p.weapon._melee_cd = 0.0
	hands._request_swing()
	_ok(bot.is_dead and is_zero_approx(bot.hp), "one bash from the hands is a kill (hp %.0f)" % bot.hp)
	_ok(LosHands.for_owner(1) == null and not Game.los_view, "a landed bash ends the streak")
	_ok(p.camera != null and p.camera.current, "camera is back on the body after the snap")
	var snap := Vector3(feet.x, feet.y + LosHands.EYE_H - eye, feet.z)
	var drift := p.global_position.distance_to(snap)
	_ok(drift < 0.45, "the body snapped to the hands (%.2f m off, at %.1f/%.1f/%.1f)" % [
		drift, p.global_position.x, p.global_position.y, p.global_position.z])
	# A landing that would put the capsule in a wall: look around the hands instead of refusing.
	var wall := StaticBody3D.new()
	var wcol := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.4, 4.0, 4.0)
	wcol.shape = wbox
	wall.add_child(wcol)
	wall.position = Vector3(6.9, 2.0, 6.0)
	add_child(wall)
	await get_tree().physics_frame
	p.is_dead = false
	p._spawn_protect = 0.0
	_ok(LosHands.launch(p), "launch next to a wall")
	var hug := LosHands.for_owner(1)
	hug.global_position = Vector3(6.55, 3.0, 6.0)
	var land := hug._landing()
	var off := -1.0
	if land.is_finite():
		off = Vector2(land.x - 6.55, land.z - 6.0).length()
	_ok(land.is_finite() and off > 0.3, "a blocked landing moves aside (%.2f m)" % off)
	LosHands.abort_for(1)
	wall.queue_free()
	await get_tree().physics_frame
	# The streak key again: out early, and the body stays where it stood.
	_ok(LosHands.launch(p) and Game.los_view, "launch for a recall")
	var hold := LosHands.for_owner(1)
	hold.global_position = Vector3(4.0, 3.0, 4.0)
	var body_pos := p.global_position
	LosHands.recall_local()
	_ok(LosHands.for_owner(1) == null and not Game.los_view, "a recall ends the streak")
	_ok(p.global_position.distance_to(body_pos) < 0.2, "a recall does not move the body")
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(0, 0.05, 0)
	p.rotation = Vector3.ZERO
	await get_tree().physics_frame
	p.velocity = Vector3.ZERO
	p.is_dead = false
	p._spawn_protect = 0.0
	_ok(LosHands.launch(p) and Game.los_view, "LOS view on for the timer")
	# The window is 5 s: still out at 4 s, gone by 6 s. Asserts the window, not the constant.
	for _i in 240:
		await get_tree().physics_frame
	_ok(Game.los_view and LosHands.for_owner(1) != null, "still out after 4 s")
	for _i in 120:
		await get_tree().physics_frame
	_ok(not Game.los_view and LosHands.for_owner(1) == null, "gone after 6 s")
	_ok(p.camera != null and p.camera.current, "camera is back on the body")
	p.velocity = Vector3.ZERO
	_ok(LosHands.launch(p) and Game.los_view, "LOS again, to die in it")
	p._spawn_protect = 0.0
	Game._shot_ctx = {}
	p.apply_hit(p.global_position + Vector3.UP, Vector3.UP, 500.0, false, -3, &"rifle")
	_ok(p.is_dead and not Game.los_view and LosHands.for_owner(1) == null, "killing the body ends the streak")
	_ok(p.camera != null and p.camera.current, "camera is back after the death")
