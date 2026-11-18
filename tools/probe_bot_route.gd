extends Node
## NOT a CI check (run_checks.sh only runs check_*): does a bot take the route hints (#270) in a real match?
## Plays an FFA with bots on each map for SECS seconds of game time and counts, per map:
##   chances  - times a hunting bot without a route came within BotRoutes.REACH of a route start (the
##              chance the picker had); picks / chances says whether pick() is too strict
##   picks    - routes taken; done = followed to the last point, dropped = stalled or interrupted
##   wallruns - wallruns started on a route vs off one (#278's own finder)
## The human pawn is parked under spawn protection so the match is the bots' own.
##   godot --headless --path . res://tools/probe_bot_route.tscn -- [maps...] [secs=60] [bots=8] [diff=1]
## (no maps: every map in Maps.ORDER; diff 0/1/2 = Easy/Medium/Hard)
const HUNT := [BotBrain.State.HUNT_FLANK, BotBrain.State.HUNT_DIRECT]
var secs := 60.0
var bots := 8
var diff := 1


func _ready() -> void:
	var maps: Array[StringName] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("secs="):
			secs = float(a.substr(5))
		elif a.begins_with("bots="):
			bots = int(a.substr(5))
		elif a.begins_with("diff="):
			diff = int(a.substr(5))
		else:
			maps.append(StringName(a))
	if maps.is_empty():
		maps = Maps.ORDER.duplicate()
	seed(270)
	var rows: PackedStringArray = []
	for m in maps:
		rows.append(await _one(m))
	Engine.time_scale = 1.0
	print("\nPROBE bot routes: %d bots, difficulty %d, %.0f s per map" % [bots, diff, secs])
	print("%-11s %7s %6s %5s %5s %8s %8s %6s" % ["map", "chances", "picks", "done", "drop", "wr route", "wr off", "pick%"])
	print("(pick% = picks / (picks + chances that were passed up))")
	for r in rows:
		print(r)
	get_tree().quit(0)


func _one(map_id: StringName) -> String:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.bot_difficulty = diff
	Game.last_bots = bots
	Game.bot_count = bots
	menu.set_match_choice(map_id, Game.MODE_FFA)
	for b in menu._bot_boxes:
		b.value = bots
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and Game._round_active and not Game.play_locked():
			break
	if me == null:
		main.queue_free()
		return "%-11s no local pawn" % map_id
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	var routes := BotRoutes.for_map(me.get_world_3d().direct_space_state, map_id)
	# Same 1/60 s physics step, more of them per wall-clock second.
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = 8.0
	var chances := 0
	var picks := 0
	var done := 0
	var dropped := 0
	var wr_route := 0
	var wr_off := 0
	var last := {} # bot instance id -> {"hint": bool, "i": int, "n": int, "wr": bool}
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		me._spawn_protect = 999.0
		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Player
			if p == null or not p.is_bot or p.is_dead or p._bot_brain == null:
				continue
			var brain: BotBrain = p._bot_brain
			var id := p.get_instance_id()
			var prev: Dictionary = last.get(id, {"hint": false, "i": 0, "n": 0, "wr": false, "near": false})
			var on := not brain._hint.is_empty()
			if on and not prev.hint:
				picks += 1
			elif prev.hint and not on:
				# _clear_hint() resets the cursor, so judge by where it was the tick before.
				if int(prev.i) >= int(prev.n) - 1:
					done += 1
				else:
					dropped += 1
			if p._wallrunning and not prev.wr:
				if on or prev.hint:
					wr_route += 1
				else:
					wr_off += 1
					if OS.has_environment("PROBE_TRACE"):
						print("TRACE off-route wallrun bot=%s t=%.1f pos=%s state=%d trick=%d cd=%.1f" % [p.name, t, p.global_position.snapped(Vector3.ONE * 0.1), brain.state, brain._trick, brain._trick_cd])
			var near := false
			if not on and HUNT.has(brain.state):
				for r in routes:
					var s: Vector3 = (r["points"] as Array)[0]
					if BotRoutes.flat_dist(s, p.global_position) <= BotRoutes.REACH:
						near = true
						break
			if near and not prev.near:
				chances += 1
			last[id] = {"hint": on, "i": brain._hint_i, "n": (brain._hint.get("points", []) as Array).size(),
					"wr": p._wallrunning, "near": near}
	Engine.time_scale = 1.0
	main.queue_free()
	Game.is_offline = true
	await get_tree().create_timer(0.5).timeout
	var pct := 100.0 * float(picks) / float(chances + picks) if chances + picks > 0 else 0.0
	return "%-11s %7d %6d %5d %5d %8d %8d %5.0f%%" % [map_id, chances, picks, done, dropped, wr_route, wr_off, pct]
