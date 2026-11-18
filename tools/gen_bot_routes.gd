extends Node
## #270: writes `data/bot_routes/<map>.json` from the map itself.
##
## The routes are not hand-written guesses: the generator bakes the map, samples walkable navmesh points,
## and asks `BotWall.find` (the very finder the bots use) whether there is a runnable wall from there in
## any of eight directions. A hit becomes a two-point route along that face, 0.7 m off it - the line the
## bot will actually sprint.
##
## Every candidate is validated first, then the file is trimmed to MAX_ROUTES round-robin over the wall
## faces, so a short wall (Foundry's roof walls) keeps a route instead of being outvoted by the long
## faces of a big map. Each map has its own seed: generating one map alone writes the same file as a
## run over all of them.
##
## The loader (`BotRoutes`) validates whatever comes out again at load time, so a map change that moves a
## wall drops the stale route instead of steering bots into it. Re-run this after editing a map.
##
##   ~/.local/bin/godot --headless --path . res://tools/gen_bot_routes.tscn -- skyline rooftops
## (no arguments: every map in `Maps.ORDER`)
## Random navmesh points per map. Small walls on a small floor (a roof) only show up in a large sample.
const SAMPLES := 3000
## m between two route starts on one face: about twice BotRoutes.REACH, so a passing bot has one in reach.
const FACE_STEP := 6.0
## A map does not need every wall: the loader walks the list on each look-up, so keep it lean.
const MAX_ROUTES := 60
const HEADINGS := 8
const OUT_DIR := "res://data/bot_routes/"
var _map := &""


func _ready() -> void:
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
	# Seeded per map: the same sample set every run, and the same whether a map is generated alone or
	# with the others, so regenerating a map is a diff and not a shuffle.
	seed(20261117 + hash(str(map_id)))
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
	var face_of := {} # route start, as text -> its face key, for the round-robin trim
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
			# One route per face, direction and FACE_STEP of the face: the face key is the plane (normal
			# and offset) at this height, both run directions share it, and a long face gets a start
			# every FACE_STEP so one is always within the loader's REACH of a bot passing by.
			var face := "%s|%s|%s" % [
				Vector3(snappedf(n.x, 0.1), snappedf(n.y, 0.1), snappedf(n.z, 0.1)),
				snappedf(n.dot(plan.point as Vector3), 0.5),
				snappedf(start.y, 1.0),
			]
			var key := "%s|%s|%s" % [
				face,
				Vector3(snappedf(along.x, 1.0), snappedf(along.y, 1.0), snappedf(along.z, 1.0)),
				snappedf(along.dot(start), FACE_STEP),
			]
			if by_key.has(key):
				continue
			var s := Vector3(snappedf(start.x, 0.1), snappedf(start.y, 0.1), snappedf(start.z, 0.1))
			face_of[str(s)] = face
			by_key[key] = {"kind": "wallrun", "points": [
				[s.x, s.y, s.z],
				[snappedf(end.x, 0.1), snappedf(end.y, 0.1), snappedf(end.z, 0.1)],
			]}
	var path := OUT_DIR + str(map_id) + ".json"
	if not _write(path, by_key.values()):
		print("GEN %s: cannot write %s" % [map_id, path])
		main.queue_free()
		return
	# Validate every candidate with the loader the game uses (same space, same checks) before the trim:
	# a route the loader drops at match start is a warning in the log nobody can act on, and trimming
	# first would spend slots on routes that are thrown away afterwards.
	var valid := BotRoutes.from_file(space, path)
	var clean := _trim(valid, face_of)
	_write(path, clean)
	print("GEN %s: %d candidates, %d valid, %d kept -> %s" % [map_id, by_key.size(), valid.size(), clean.size(), path])
	main.queue_free()
	Game.is_offline = true
	await get_tree().create_timer(0.5).timeout


## At most MAX_ROUTES, taken round-robin over the faces: every wall gets its first route before any
## wall gets a second, so a short wall (Foundry's 7.1 m roof walls) is not outvoted by long ones.
func _trim(valid: Array, face_of: Dictionary) -> Array:
	var by_face := {}
	for r in valid:
		var pts: Array = []
		for q in (r["points"] as Array):
			var v: Vector3 = q
			pts.append([snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)])
		var s: Vector3 = (r["points"] as Array)[0]
		var face: String = face_of.get(str(Vector3(snappedf(s.x, 0.1), snappedf(s.y, 0.1), snappedf(s.z, 0.1))), str(s))
		if not by_face.has(face):
			by_face[face] = []
		(by_face[face] as Array).append({"kind": str(r["kind"]), "points": pts})
	var out: Array = []
	var round := 0
	while out.size() < MAX_ROUTES:
		var added := false
		for face in by_face:
			var list: Array = by_face[face]
			if round < list.size() and out.size() < MAX_ROUTES:
				out.append(list[round])
				added = true
		if not added:
			break
		round += 1
	return out


func _write(path: String, routes: Array) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"routes": routes}, "  "))
	f.close()
	return true
