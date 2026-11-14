extends Node
## #150 headless: a bot sprints when closing, jumps a lip the step-up cannot clear, turns to
## whoever just shot them, and backs off instead of trading while low.
##   godot --headless res://tools/check_bot_smart.tscn   → "BOT SMART CHECK OK"
const BASE := Vector3(0, 240, 0)
var fails := 0
var bot: Player
var other: Player
var me: Player
var brain: BotBrain
var _boxes: Array[StaticBody3D] = []


var fail_msgs: Array[String] = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1
		fail_msgs.append(msg)


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	s.shape = sh
	b.add_child(s)
	get_tree().root.add_child(b)
	b.global_position = pos
	_boxes.append(b)
	return b


func _clear_boxes() -> void:
	for b in _boxes:
		b.free()
	_boxes.clear()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _park(p: Player) -> void:
	p.is_dead = true
	p.collision_layer = 0
	p.collision_mask = 0
	p.velocity = Vector3.ZERO
	p.global_position = BASE + Vector3(0, 40, 0)


func _wake(p: Player, pos: Vector3) -> void:
	p.is_dead = false
	p.collision_layer = 2
	p.collision_mask = 1
	p.hp = Player.MAX_HP
	p.velocity = Vector3.ZERO
	p.global_position = pos


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	# Hard, because this check tests movement, aim and jumps, not awareness: a Hard bot is omniscient and
	# therefore stands at `_home` exactly like every bot did before awareness existed. A Medium bot now
	# patrols when it knows nobody, which is correct in a match and noise for these assertions. Awareness
	# has its own check (check_bot_aware).
	Game.bot_difficulty = Game.BOT_HARD
	Game.last_bot_difficulty = Game.BOT_HARD
	Game.bot_count = 2
	Game.last_bots = 2
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	for b in menu._bot_boxes:
		b.value = 2
	menu.play_local_pressed.emit()
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		var bots: Array[Player] = []
		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Player
			if p and p.is_bot:
				bots.append(p)
		if me and bots.size() >= 2 and Game._round_active and not Game.play_locked():
			bot = bots[0]
			other = bots[1]
			break
	_ok(bot != null and other != null and me != null, "round running with two bots")
	if bot == null or me == null:
		_done()
		return
	brain = bot._bot_brain
	_ok(brain != null, "test bot has a brain")
	if brain == null:
		_done()
		return
	other._bot_brain = null
	brain.agent = null
	_box(BASE + Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	_park(me)
	_park(other)
	bot.global_position = BASE + Vector3(0, 0.2, 0)
	bot.velocity = Vector3.ZERO
	brain._home = bot.global_position
	# Poll for the floor instead of trusting a fixed frame count: the box is added to the physics world
	# this frame, and a loaded runner needs more than eight frames to settle a pawn on it.
	var stood := false
	for i in 90:
		await _frames(1)
		if bot.is_on_floor():
			stood = true
			break
	brain._home = bot.global_position
	bot.velocity = Vector3.ZERO
	await _frames(3)
	_ok(stood and bot.is_on_floor(), "bot stood on the test floor (y %.2f)" % bot.global_position.y)
	await _ledges()
	await _sprint()
	await _threat_and_retreat()
	await _tricks()
	_done()


func _ledges() -> void:
	var dir := Vector3(0, 0, 1)
	# A body added this frame is not in the physics world yet. Stand still while it appears.
	var feet := bot.global_position
	_box(feet + Vector3(0, 0.4, 1.0), Vector3(2.0, 0.8, 0.6))
	brain._home = feet
	bot.velocity = Vector3.ZERO
	await _frames(2)
	# Poll for the box to exist in the physics world instead of trusting two frames: a body added this
	# frame is not there yet, and under load the probe then reads -1.0 ("no ledge") on a loaded runner.
	var lip := -1.0
	for i in 40:
		lip = brain._ledge_climb(dir)
		if lip >= 0.0:
			break
		await _frames(1)
	_ok(lip > 0.5 and lip < 1.1, "0.8 m lip reads as a jump (climb %.2f)" % lip)
	# _try_jump_ledge() bails on `not is_on_floor()`, and after the zeroed velocity the pawn can be a
	# frame airborne. Wait for the floor instead of assuming it: that assumption is what read as a
	# flaky FAIL on a loaded runner.
	var grounded := false
	for i in 20:
		await _frames(1)
		if bot.is_on_floor():
			grounded = true
			break
	_ok(grounded, "the bot is back on the test floor before the jump")
	bot.velocity = Vector3.ZERO
	var jumped := brain._try_jump_ledge(dir)
	_ok(jumped and bot.velocity.y >= Player.JUMP_SPEED - 0.01, "on the floor, that lip sets the jump")
	bot.velocity = Vector3.ZERO
	_clear_boxes()
	_box(BASE + Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	feet = bot.global_position
	_box(feet + Vector3(0, 0.1, 1.0), Vector3(2.0, 0.2, 0.6))
	brain._home = feet
	await _frames(2)
	_ok(brain._ledge_climb(dir) < 0.0, "a 0.2 m curb is a step, not a jump (climb %.2f)" % brain._ledge_climb(dir))
	_clear_boxes()
	_box(BASE + Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	feet = bot.global_position
	_box(feet + Vector3(0, 1.5, 1.0), Vector3(2.0, 3.0, 0.6))
	brain._home = feet
	await _frames(2)
	_ok(brain._ledge_climb(dir) < 0.0, "a 3 m wall is too tall to jump (climb %.2f)" % brain._ledge_climb(dir))
	_clear_boxes()
	_box(BASE + Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	await _frames(2)


func _sprint() -> void:
	Game.set_hp(bot, Player.MAX_HP)
	brain._hurt_retreat_left = 0.0
	brain._threat = null
	brain._threat_left = 0.0
	brain._hunt_direct = true
	_wake(me, bot.global_position + Vector3(0, 0, 40))
	_park(other)
	bot.velocity = Vector3.ZERO
	var peak := 0.0
	var sprinting := false
	for i in 45:
		await get_tree().physics_frame
		peak = maxf(peak, Vector2(bot.velocity.x, bot.velocity.z).length())
		sprinting = sprinting or bot.is_sprinting
	print("  hunt peak speed %.2f m/s, sprint flag %s" % [peak, sprinting])
	_ok(peak > 9.0 and sprinting, "hunt closes at a sprint, not a walk")
	_park(me)


func _threat_and_retreat() -> void:
	var feet := bot.global_position
	_wake(me, feet + Vector3(6, 0, 0))
	_wake(other, feet + Vector3(0, 0, 18))
	bot.velocity = Vector3.ZERO
	brain._home = feet
	brain._target = null
	brain._threat = null
	brain._threat_left = 0.0
	brain._retarget_t = 0.0
	brain._hurt_retreat_left = 0.0
	await _frames(2)
	brain._retarget_t = 0.0
	var nearest: Player = brain._pick_target(0.0)
	_ok(nearest == me, "with no threat, the closer pawn is the target (got %s)" % _who(nearest))
	brain.note_threat(other)
	brain._retarget_t = 0.0
	var turned: Player = brain._pick_target(0.0)
	_ok(turned == other, "a hit from the farther pawn pulls the aim (got %s)" % _who(turned))
	Game.set_hp(bot, 30.0)
	var before := bot.global_position.distance_to(me.global_position)
	# The retreat has its own cooldown and an earlier phase can have started one: clear it, or this
	# step silently tests nothing (it read "low HP starts a retreat" FAIL on a loaded machine).
	brain._retreat_cd = 0.0
	brain.note_threat(me)
	_ok(brain._hurt_retreat_left > 0.0, "low HP starts a retreat")
	var after := before
	var sprinting := false
	for i in 50:
		await get_tree().physics_frame
		after = bot.global_position.distance_to(me.global_position)
		sprinting = sprinting or bot.is_sprinting
	print("  retreat %.2f m -> %.2f m" % [before, after])
	_ok(after > before + 1.5 and sprinting, "low HP bot sprints away from the shooter")


## The three parkour moves. Bots run the same Movement code as a human (no `is_bot` shortcut any more),
## so what is tested here is the shared slide, dive and wallrun, driven by the bot's own keys.
func _tricks() -> void:
	_clear_boxes()
	_box(BASE + Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	_park(me)
	# Drive the bot by hand: its own AI rewrites velocity and state every frame, which would fight
	# every move this test sets up.
	bot.set_physics_process(false)
	other.set_physics_process(false)
	_wake(bot, BASE + Vector3(0, 1.2, 0))
	_wake(other, BASE + Vector3(0, 0.5, 8.0))
	await _frames(2)

	# Slide: on the floor, closing on a target at sprint speed.
	brain._target = other
	brain._in_fight = true
	brain._crouch_hold = 0.0
	brain._crouch_press = false
	bot._slide_cd = 0.0
	bot._sliding = false
	bot.is_sprinting = true
	bot.crouch = 0.0
	bot.velocity = Vector3(0.0, -8.0, 0.0)
	for i in 10:
		bot.move_and_slide() # settle: is_on_floor() is only real after a move
	var slid := false
	for i in 8:
		bot.velocity = Vector3(0.0, 0.0, -Player.SPRINT_SPEED)
		brain._tick_tricks(dt)
		if bot._sliding:
			slid = true
			break
	var slide_speed := Vector2(bot.velocity.x, bot.velocity.z).length()
	_ok(slid, "bot slides when it closes on a target at sprint speed")
	_ok(slid and slide_speed >= Player.SPRINT_SPEED - 0.1, "the slide keeps sprint speed (%.1f m/s)" % slide_speed)
	bot._sliding = false
	bot.crouch = 0.0
	bot._apply_stance()

	# Dive: in the air, falling, target below.
	brain._in_fight = false
	brain._target = other
	bot._dive_cd = 0.0
	bot._dive_used = false
	bot._diving = false
	bot._wallrunning = false
	bot.global_position = BASE + Vector3(0, 6.0, -4.0)
	bot.velocity = Vector3(0.0, -6.0, Player.SPRINT_SPEED)
	bot.move_and_slide() # one move so is_on_floor() turns false again
	var dove := false
	for i in 6:
		brain._tick_tricks(dt)
		if bot._diving:
			dove = true
			break
	_ok(dove, "bot dives at a target below it")

	# Wallrun: in the air, sprint held, flying along a wall 0.6 m away.
	bot._diving = false
	bot._roll_t = 0.0
	bot._wallrunning = false
	bot._wallruns_air = 0
	bot._wall_key = ""
	bot._surf_t = 0.0
	bot._dive_used = false
	_box(BASE + Vector3(3.0, 6.0, -10.0), Vector3(1.0, 30.0, 80.0))
	# A body added this frame is not in the physics world yet: let it appear before probing for it.
	await _frames(2)
	bot.global_position = BASE + Vector3(1.9, 6.0, -30.0)
	bot.velocity = Vector3(0.0, 0.0, Player.SPRINT_SPEED)
	bot.move_and_slide() # one move so is_on_floor() is false and the wall contact is fresh
	var ran := false
	for i in 8:
		bot.velocity.y = 0.0
		brain._tick_tricks(dt)
		if bot._wallrunning:
			ran = true
			break
	_ok(ran, "bot wallruns along a wall it is flying past")


func _who(p: Player) -> String:
	if p == null:
		return "none"
	if p == me:
		return "player"
	if p == other:
		return "other bot"
	return str(p.peer_id)


func _done() -> void:
	print("BOT SMART CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	# The runner only keeps the tail of a check's output, so a red run used to hide which assertion
	# failed when it was early in the list. Print them last.
	for m in fail_msgs:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
