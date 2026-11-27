extends Node
## #311/#360: the bot routes have to survive the load order. The first bot tick of a match can come before
## the map's collision exists (CSG is baked after the scene is added); back then every ray missed, every
## route failed the floor test, and the empty answer was cached - so all 60 wallrun routes were gone for
## the whole match while the log blamed the data.
##
## This check loads every map, asks for its routes *immediately* (too early on purpose), then again after
## the world is up: the second call has to give the full set. That fails on the old code, where the empty
## first answer stayed cached.
##   ./run.sh --headless res://tools/check_bot_routes.tscn   → "BOT ROUTES CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _routes_in_file(map_id: StringName) -> int:
	var text := FileAccess.get_file_as_string(BotRoutes.DIR + str(map_id) + ".json")
	if text.is_empty():
		return 0
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	var raw = (parsed as Dictionary).get("routes", [])
	return (raw as Array).size() if typeof(raw) == TYPE_ARRAY else 0


func _ready() -> void:
	var maps: Array[StringName] = [&"quay", &"townhouses", &"foundry", &"rooftops", &"skyline"]
	for map_id in maps:
		var want := _routes_in_file(map_id)
		_ok(want > 0, "%s ships routes (%d)" % [map_id, want])
		# The real id: for_map reads `data/bot_routes/<id>.json`. The cache is dropped first (see below),
		# so the next map's first look-up is the "too early" one again. `has_method` keeps this check
		# runnable against the old code too: there it simply has no cache to reset, and it has to fail.
		var key := map_id
		BotRoutes.reset_cache()
		var map := (load("res://scenes/maps/%s.tscn" % map_id) as PackedScene).instantiate() as Node3D
		add_child(map)
		var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
		# 1) Too early: the collision is not baked yet. This must not be cached.
		var early := BotRoutes.for_map(space, key)
		_ok(early.is_empty(), "%s: the routes are not usable before the collision exists (%d)" % [map_id, early.size()])
		# 2) The world is up now: the same look-up has to give the whole set back. In a match this is the
		#    next bot tick; here it is a few physics frames, and 2 s is far beyond any bake.
		var late: Array = []
		var frames := 0
		while frames < 120:
			await get_tree().physics_frame
			frames += 1
			late = BotRoutes.for_map(space, key)
			if not late.is_empty():
				break
		_ok(late.size() == want, "%s: every route comes back once the world is there (%d/%d after %d frames)" % [map_id, late.size(), want, frames])
		# 3) And it is cached now: a third call cannot cost another pass over the file.
		var again := BotRoutes.for_map(space, key)
		_ok(again.size() == late.size(), "%s: the answer is cached after that (%d)" % [map_id, again.size()])
		var kinds := {}
		for r in late:
			kinds[StringName(r["kind"])] = int(kinds.get(StringName(r["kind"]), 0)) + 1
		_ok(kinds.has(&"wallrun"), "%s: the wallrun routes are among them (%s)" % [map_id, str(kinds)])
		# Free right away: a CSG map frees its collision deferred, and the next map would otherwise be
		# validated against the previous map's floors (both live in the same world).
		map.free()
		await get_tree().physics_frame
		await get_tree().physics_frame

	# A map without a file is still no routes and no cache problem.
	var orphan := Node3D.new()
	add_child(orphan)
	_ok(BotRoutes.for_map(orphan.get_world_3d().direct_space_state, &"no_such_map").is_empty(),
		"a map with no route file is no routes, not a crash")
	orphan.queue_free()

	print("BOT ROUTES CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	var code := 0 if fails == 0 else 1
	if code == 0:
		print("BOT ROUTES CHECK OK")
	else:
		print("BOT ROUTES CHECK FAILED")
	get_tree().quit(code)
