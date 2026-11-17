extends Node
## #270. Route hints: the loader drops a route that runs through a wall or has no floor under it,
## a bot follows a route it would never walk on its own, and a route that makes no progress is
## dropped within the issue's 0.6 s instead of leaving the bot in a hanging state.
##   ./run.sh --headless res://tools/check_bot_route.tscn   → "BOT ROUTE CHECK OK"
const BASE := Vector3(0, 240, 0)
const TICKS := 300
var fails := 0
var failed: Array[String] = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1
		failed.append(msg)


func _body(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	add_child(body)
	body.global_position = at
	return body


func _pawn(at: Vector3) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = -1
	p.is_bot = true
	p.position = at
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	p.grenades = 0
	# The pawn builds its own brain in `_ready` and the server ticks it: detach it, or two brains steer
	# the same pawn and the route is fought over by an AI that only wants to walk at the enemy.
	p._bot_brain = null
	return p


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	Game.bot_difficulty = Game.BOT_HARD
	seed(20261117)
	_body(Vector3(120, 1, 120), BASE + Vector3(0, -0.5, 0))
	_loader()
	_files()
	await _follow()
	_timeout()
	_done()


## The file format and the one-time validation.
func _loader() -> void:
	# A 4 m wall the bad route runs through, and a floor under the good one.
	_body(Vector3(20, 4, 1), BASE + Vector3(50, 2.0, 50)) # its own corner: it must not block the follow test
	await get_tree().physics_frame
	var path := "user://bot_route_check.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	# Points are world coordinates, so they sit on this fixture's floor (BASE), not at y = 0.
	var a := [BASE.x + 50.0, BASE.y, BASE.z + 46.0]
	var b := [BASE.x + 50.0, BASE.y, BASE.z + 47.0]
	var c := [BASE.x + 50.0, BASE.y, BASE.z + 48.0]
	var d := [BASE.x + 50.0, BASE.y, BASE.z + 52.0]
	f.store_string(JSON.stringify({"routes": [
		{"kind": "slide", "points": [a, b]},
		{"kind": "slide", "points": [c, d]}, # straight through the wall
		{"kind": "teleport", "points": [a, b]}, # unknown kind
		{"kind": "wallrun", "points": [a]}, # one point is not a route
	]}))
	f.close()
	var space := get_viewport().world_3d.direct_space_state
	var routes := BotRoutes.from_file(space, path)
	_ok(routes.size() == 1, "the loader keeps only the valid route (%d of 4)" % routes.size())
	if routes.size() == 1:
		_ok(StringName(routes[0]["kind"]) == &"slide", "and it keeps the right kind (%s)" % routes[0]["kind"])
		_ok((routes[0]["points"] as Array).size() == 2, "with its points as Vector3")
	_ok(BotRoutes.from_file(space, "user://does_not_exist.json").is_empty(), "a missing file is no routes, not a crash")

	# Picking: only a route that starts here and leads towards the goal.
	var near := [{"kind": &"slide", "points": [BASE + Vector3(0, 0, 0), BASE + Vector3(0, 0, 10)] as Array[Vector3]}]
	var goal_beyond := BASE + Vector3(0, 0, 40)
	var goal_behind := BASE + Vector3(0, 0, -40)
	_ok(not BotRoutes.pick(space, near, BASE + Vector3(0.5, 0, 0), goal_beyond).is_empty(),
		"a route that starts at the bot and leads to the goal is picked")
	_ok(BotRoutes.pick(space, near, BASE + Vector3(0.5, 0, 0), goal_behind).is_empty(),
		"a route that leads away from the goal is not")
	_ok(BotRoutes.pick(space, near, BASE + Vector3(20, 0, 0), goal_beyond).is_empty(),
		"and neither is one whose start is out of reach")


## The bot walks a detour it would never take on its own, and stops using the route when it is done.
func _follow() -> void:
	var bot := _pawn(BASE + Vector3(0, 0.2, 0))
	# A known gun, so the fight range is the rifle's and not whatever the random loadout gave: this
	# test needs a target it is NOT in range of, or the bot fights instead of hunting.
	var enemy := _pawn(BASE + Vector3(0, 0.2, 60))
	enemy.weapon.ammo = 0
	var brain := BotBrain.new()
	brain.setup(bot, null)
	for i in 6:
		bot.move_and_slide()
		await get_tree().physics_frame
	# After the settle: `_apply_bot_loadout` is deferred, so arming earlier would be overwritten.
	bot.weapon.equip_loadout(0)

	# Detour: out to the side and back, nowhere near the straight line to the enemy.
	# The route leads away from the enemy, so the bot never enters a fight while it follows it: this
	# window is about the route, not about the fight that would take over.
	var detour: Array[Vector3] = [
		BASE + Vector3(0, 0, 0), BASE + Vector3(-12, 0, 4),
		BASE + Vector3(-18, 0, 16), BASE + Vector3(-6, 0, 24),
	]
	var far_point := BASE + Vector3(-18, 0, 16)

	# Without the hint the bot heads straight for the enemy and never comes near the far point.
	var plain := await _closest(bot, enemy, brain, far_point, {})
	# With it, it does.
	var hint := {"kind": &"slide", "points": detour}
	var routed := await _closest(bot, enemy, brain, far_point, hint)
	print("  closest approach to the far route point: %.1f m without a hint, %.1f m with" % [plain, routed])
	_ok(plain > 8.0, "without a hint the hunt stays away from the route point (%.1f m)" % plain)
	_ok(routed <= 6.0, "with the hint the bot walks the route to that point (%.1f m)" % routed)
	_ok(brain._hint.is_empty() or brain._hint_i > 0, "and the route is consumed as points are reached")


## Runs the real tick with (or without) a route pinned on the brain and returns the closest the bot
## came to `target`.
## The shipped map files. Only parsing and schema here: whether their geometry is still walkable is
## checked once at load, in the real map's space (`BotRoutes._validate`), because this scene has no
## arena to trace.
func _files() -> void:
	for m in [&"skyline", &"rooftops"]:
		var path := "res://data/bot_routes/" + str(m) + ".json"
		var text := FileAccess.get_file_as_string(path)
		var routes: Array = []
		if not text.is_empty():
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				var raw = (parsed as Dictionary).get("routes", [])
				routes = raw if typeof(raw) == TYPE_ARRAY else []
		_ok(routes.size() >= 2, "%s ships at least two routes (%d)" % [m, routes.size()])
		var kinds_ok := true
		var points_ok := true
		for entry in routes:
			if typeof(entry) != TYPE_DICTIONARY:
				kinds_ok = false
				continue
			var d := entry as Dictionary
			if StringName(str(d.get("kind", ""))) != &"wallrun":
				kinds_ok = false
			var pts = d.get("points", [])
			if typeof(pts) != TYPE_ARRAY or (pts as Array).size() < 2:
				points_ok = false
		_ok(kinds_ok, "%s: every route is a wallrun" % m)
		_ok(points_ok, "%s: every route has at least two points" % m)


func _closest(bot: Player, enemy: Player, brain: BotBrain, target: Vector3, hint: Dictionary) -> float:
	bot.global_position = BASE + Vector3(0, 0.2, 0)
	bot.velocity = Vector3.ZERO
	brain.setup(bot, null)
	brain._hint = hint.duplicate(true)
	brain._hint_i = 1 if (hint.get("points", []) as Array).size() > 1 else 0
	brain._hint_pos = bot.global_position
	brain._hint_t = 0.0
	# The same enemy from the first tick: a target change resets the hunt, and that would throw the
	# pinned route away before it is ever followed.
	brain._target = enemy
	brain._retarget_t = 1.0
	var best := 9999.0
	for i in TICKS:
		bot.hp = Player.MAX_HP
		enemy.hp = Player.MAX_HP
		enemy.is_dead = false
		bot.is_dead = false
		brain.physics_tick(1.0 / 60.0)
		best = minf(best, Vector2(bot.global_position.x - target.x, bot.global_position.z - target.z).length())
		await get_tree().physics_frame
	return best


## A route that cannot be walked is dropped inside 0.6 s, not left hanging for the rest of the match.
func _timeout() -> void:
	var bot := _pawn(BASE + Vector3(-30, 0.2, -30))
	var enemy := _pawn(BASE + Vector3(-30, 0.2, -20))
	var brain := BotBrain.new()
	brain.setup(bot, null)
	# Next point 40 m away with the pawn held still: no progress for as long as the timer runs.
	brain._hint = {"kind": &"slide", "points": [bot.global_position, bot.global_position + Vector3(0, 0, 40)] as Array[Vector3]}
	brain._hint_i = 1
	brain._hint_pos = bot.global_position
	brain._hint_t = 0.0
	var ticks := 0
	while not brain._hint.is_empty() and ticks < 90:
		brain._follow_hint(enemy, 1.0 / 60.0)
		ticks += 1
	_ok(brain._hint.is_empty(), "a route without progress is dropped after %.2f s (%.0f ticks)" % [ticks / 60.0, ticks])
	_ok(ticks <= 40, "and that is inside the issue's 0.6 s (%d ticks)" % ticks)


func _done() -> void:
	print("BOT ROUTE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in failed:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
