extends Node
## #270: writes `data/bot_routes/<map>.json` from the map itself.
##
## The routes are not hand-written guesses: the generator bakes the map, samples walkable navmesh points,
## and asks `BotWall.find` (the very finder the bots use) whether there is a runnable wall from there in
## any of eight directions. A hit becomes a two-point route along that face, 0.7 m off it - the line the
## bot will actually sprint.
##
## The loader (`BotRoutes`) validates whatever comes out again at load time, so a map change that moves a
## wall drops the stale route instead of steering bots into it. Re-run this after editing a map.
##
##   ~/.local/bin/godot --headless --path . res://tools/gen_bot_routes.tscn -- skyline rooftops
## (no arguments: every map in `Maps.ORDER`)
const SAMPLES := 220
## A map does not need every wall: the loader walks the list on each look-up, so keep it lean.
const MAX_ROUTES := 60
const HEADINGS := 8
const OUT_DIR := "res://data/bot_routes/"
var _map := &""


func _ready() -> void:
	seed(20261117) # the same sample set every run, so regenerating a map is a diff and not a shuffle
	var args := OS.get_cmdline_user_args()
	var list: Array[StringName] = []
	for a in args:
		list.append(StringName(a))
	if list.is_empty():
		list = Maps.ORDER.duplicate()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for m in list:
		await _one(m)
	get_tree().quit(0)


## One match on `map_id`, sampled once the navmesh is baked, then straight back out.
func _one(map_id: StringName) -> void:
	_map = map_id
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 0
	Game.bot_count = 0
	menu.set_match_choice(map_id, Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and Game._round_active and not Game.play_locked():
			break
	if me == null:
		print("GEN %s: no local pawn, skipped" % map_id)
		main.queue_free()
		return
	var agent := me.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent == null:
		print("GEN %s: no navigation agent on the pawn, skipped" % map_id)
		main.queue_free()
		return
	var map := agent.get_navigation_map()
	# A baked map is the gate: closest-point queries before the first synchronisation are errors.
	for i in 600:
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame
		if i % 60 == 0:
			NavigationServer3D.map_force_update(map)
	var space := me.get_world_3d().direct_space_state
	var by_key := {}
	for i in SAMPLES:
		var p := NavigationServer3D.map_get_random_point(map, agent.navigation_layers, true)
		if p == Vector3.ZERO:
			continue
		for h in HEADINGS:
			var heading := Vector3.RIGHT.rotated(Vector3.UP, TAU * float(h) / float(HEADINGS))
			var plan := BotWall.find(space, p, heading, [])
			if plan.is_empty():
				continue
			var along: Vector3 = plan.along
			var n: Vector3 = plan.n
			var start := Vector3((plan.point as Vector3).x, p.y, (plan.point as Vector3).z) + n * BotWall.OFFSET
			var end := start + along * BotWall.MIN_LEN
			# Round to 0.5 m so near-identical samples from one face collapse into one route.
			# Round to 2 m: samples along one face differ by centimetres, and sixty routes is plenty.
			var key := "%s|%s" % [
				Vector3(snappedf(start.x, 2.0), snappedf(start.y, 2.0), snappedf(start.z, 2.0)),
				Vector3(snappedf(along.x, 1.0), snappedf(along.y, 1.0), snappedf(along.z, 1.0)),
			]
			if by_key.has(key):
				continue
			by_key[key] = {"kind": "wallrun", "points": [
				[snappedf(start.x, 0.1), snappedf(start.y, 0.1), snappedf(start.z, 0.1)],
				[snappedf(end.x, 0.1), snappedf(end.y, 0.1), snappedf(end.z, 0.1)],
			]}
	var routes: Array = by_key.values()
	if routes.size() > MAX_ROUTES:
		# Even spread over the map instead of "whatever was sampled first".
		var kept: Array = []
		for i in MAX_ROUTES:
			kept.append(routes[int(floor(float(i) * float(routes.size()) / float(MAX_ROUTES)))])
		routes = kept
	var path := OUT_DIR + str(map_id) + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("GEN %s: cannot write %s" % [map_id, path])
		main.queue_free()
		return
	f.store_string(JSON.stringify({"routes": routes}, "  "))
	f.close()
	# Validate straight away with the loader the game uses (same space, same checks) and keep only what
	# still loads: a route the loader drops at match start is a warning in the log nobody can act on.
	var valid := BotRoutes.from_file(space, path)
	var clean: Array = []
	for r in valid:
		var pts: Array = []
		for q in (r["points"] as Array):
			var v: Vector3 = q
			pts.append([snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)])
		clean.append({"kind": str(r["kind"]), "points": pts})
	var clean_file := FileAccess.open(path, FileAccess.WRITE)
	if clean_file != null:
		clean_file.store_string(JSON.stringify({"routes": clean}, "  "))
		clean_file.close()
	print("GEN %s: %d written, %d valid at load -> %s" % [map_id, clean.size(), valid.size(), path])
	main.queue_free()
	Game.is_offline = true
	await get_tree().create_timer(0.5).timeout
