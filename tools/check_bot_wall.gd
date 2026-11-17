extends Node
## BotWall (the raycast wall finder bots use to wallrun) on real test geometry, headless, no match and no pawn:
## a long wall beside the heading is found and described, and every reason to refuse it refuses it: a wall the bot
## runs INTO, a wall too short, too low, or with no floor under the run line. Also pins the relations between the
## tunables (a bot that enters at TRICK_MIN_SPEED must still start the wallrun; it must jump off before it ends).
##   godot --headless res://tools/check_bot_wall.tscn   → "BOT WALL CHECK OK"
var fails := 0
var failed: Array[String] = []
## Far above the map so nothing else is in range; the test floor is the only floor.
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
	add_child(b) # not root: root is still busy setting up its children during this _ready, and the add fails
	b.global_position = center


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	# Tunables first: they need no geometry.
	var easy: Dictionary = Game.BOT_PROFILES[Game.BOT_EASY]
	var med: Dictionary = Game.BOT_PROFILES[Game.BOT_MEDIUM]
	var hard: Dictionary = Game.BOT_PROFILES[Game.BOT_HARD]
	_ok(float(easy.trick) == 0.0 and float(easy.trick) < float(med.trick) and float(med.trick) < float(hard.trick)
		and float(hard.trick) <= 1.0, "trick chance: Easy never, Medium sometimes, Hard most (<= 1)")
	_ok(BotBrain.TRICK_MIN_SPEED * cos(BotWall.ENTRY_ANGLE) >= Player.WALLRUN_MIN_SPEED,
		"entering at the minimum speed still leaves WALLRUN_MIN_SPEED along the wall")
	_ok(BotBrain.TRICK_JUMP_AT < Player.WALLRUN_TIME - 0.2, "the wall jump comes before the run times out")
	_ok(BotWall.MIN_LEN <= BotBrain.TRICK_MIN_SPEED * BotBrain.TRICK_JUMP_AT, "the run line is no longer than the bot runs")
	_ok(BotWall.SCAN_ANGLES.size() >= 2 and BotWall.RANGE > 0.0, "scan fan is set up")

	# Geometry: a 1 m floor slab (top at BASE.y), and walls whose faces point at -z or +z.
	_box(BASE + Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	_box(BASE + Vector3(0, 2.0, 3.5), Vector3(40, 4, 1)) # A: long, tall wall; face at z = 3, normal -z
	_box(BASE + Vector3(0, 2.0, -20.5), Vector3(3, 4, 1)) # B: 3 m of wall, face at z = -20, normal +z
	_box(BASE + Vector3(0, 0.75, 30.5), Vector3(40, 1.5, 1)) # C: long but only 1.5 m high, face at z = 30
	_box(BASE + Vector3(200, 2.0, 3.5), Vector3(40, 4, 1)) # D: like A, but nothing under it
	await _frames(3)
	var space := get_viewport().world_3d.direct_space_state
	var ex: Array[RID] = []

	# A: running +x, the wall 3 m to the side.
	var plan := BotWall.find(space, BASE + Vector3(-12, 0, 0), Vector3.RIGHT, ex)
	_ok(not plan.is_empty(), "a long tall wall beside the heading is found")
	if not plan.is_empty():
		_ok((plan.n as Vector3).is_equal_approx(Vector3(0, 0, -1)), "the face normal points back at the bot (%s)" % str(plan.n))
		_ok((plan.along as Vector3).is_equal_approx(Vector3(1, 0, 0)), "the run goes the way the bot is heading (%s)" % str(plan.along))
		_ok(float(plan.dist) > 0.0 and float(plan.dist) <= BotWall.RANGE, "the wall is within scan range (%.1f m)" % float(plan.dist))
		var e := BotWall.entry_dir(plan)
		_ok(is_equal_approx(e.length(), 1.0) and absf(e.y) < 0.001, "entry direction is flat and unit length")
		_ok(is_equal_approx(e.dot(plan.along), cos(BotWall.ENTRY_ANGLE)), "the entry keeps cos(ENTRY_ANGLE) of the speed along the wall")
		_ok(e.dot(-(plan.n as Vector3)) > 0.5, "the entry leans into the face")
	# The same wall from the other side of the heading (mirrored): found with the normal flipped.
	var mirrored := BotWall.find(space, BASE + Vector3(12, 0, 6), Vector3.LEFT, ex)
	_ok(not mirrored.is_empty() and (mirrored.n as Vector3).is_equal_approx(Vector3(0, 0, 1)) and (mirrored.along as Vector3).is_equal_approx(Vector3(-1, 0, 0)),
		"a wall on the other side is found too (face to +z, running -x)")

	# Refusals.
	_ok(BotWall.find(space, BASE + Vector3(0, 0, 0), Vector3(0, 0, 1), ex).is_empty(), "running straight INTO a wall is not a wallrun")
	_ok(BotWall.find(space, BASE + Vector3(-1.4, 0, -17), Vector3.RIGHT, ex).is_empty(), "a 3 m wall is too short to run")
	_ok(BotWall.find(space, BASE + Vector3(-12, 0, 27), Vector3.RIGHT, ex).is_empty(), "a 1.5 m wall is too low to keep touching")
	_ok(BotWall.find(space, BASE + Vector3(188, 0, 0), Vector3.RIGHT, ex).is_empty(), "no floor under the run line: refused (roof edge over a drop)")
	_ok(BotWall.find(space, BASE + Vector3(-12, 0, -10), Vector3.RIGHT, ex).is_empty(), "open floor and no wall in range: nothing")
	_ok(BotWall.find(space, BASE + Vector3(-12, 0, 0), Vector3.ZERO, ex).is_empty(), "no heading: nothing")

	# Floor probe (also used before a wall jump).
	_ok(BotWall.floor_below(space, BASE + Vector3(0, 0, 10), ex), "floor_below: floor under a point on the slab")
	_ok(not BotWall.floor_below(space, BASE + Vector3(200, 0, 0), ex), "floor_below: nothing under a point off the slab")
	_ok(not BotWall.floor_below(space, BASE + Vector3(0, 40, 10), ex), "floor_below: a point 40 m up is too far above the floor")

	await _drive_wall()
	_done()


## The trigger itself, in the real tick order: sprinting along wall A, the brain jumps at it and
## `Movement.tick_wallrun` (the same code a human runs) has to take over. Without this the finder can
## be perfect and a bot still never runs a wall - which is exactly what the live probe showed (#278).
func _drive_wall() -> void:
	Game.bot_difficulty = Game.BOT_HARD # the highest trick chance; the loop below retries the dice anyway
	var bot := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	bot.peer_id = -1
	bot.is_bot = true
	bot.position = BASE + Vector3(-12, 0.2, 0.5)
	bot.set_physics_process(false)
	bot.set_process(false)
	add_child(bot)
	bot.grenades = 0
	var brain := BotBrain.new()
	brain.setup(bot, null)
	await _frames(4)
	for i in 8:
		bot.move_and_slide() # settle: is_on_floor() is only re-derived by a move
	var dt := 1.0 / 60.0
	var started := false
	for attempt in 60:
		bot.velocity = Vector3(Player.SPRINT_SPEED, 0.0, 0.0)
		brain._trick_cd = 0.0
		brain._try_start_wall_trick()
		if brain._trick == BotBrain.Trick.AIR:
			started = true
			break
	var runs := 0
	var running_ticks := 0
	var was := false
	if started:
		for i in 110:
			# The same gravity the brain applies at the top of physics_tick: without it the jump
			# velocity never decays and the chest climbs over any wall within a tenth of a second.
			if not bot.is_on_floor():
				bot.velocity.y += float(bot.get_gravity().y) * dt
			brain._tick_tricks(dt)
			bot.move_and_slide()
			if bot._wallrunning and not was:
				runs += 1
			if bot._wallrunning:
				running_ticks += 1
			was = bot._wallrunning
	_ok(started, "the dice eventually start a trick at a long wall (60 tries, chance %.1f)" % float(Game.bot_profile().trick))
	_ok(runs >= 1, "the jump at the wall becomes a real wallrun (%d runs)" % runs)
	_ok(running_ticks >= 25, "and the run lasts (%.2f s of wallrunning)" % (running_ticks * dt))


func _done() -> void:
	print("BOT WALL CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in failed:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
