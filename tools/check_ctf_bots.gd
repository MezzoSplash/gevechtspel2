extends Node
## #160 headless bot smoke: CTF on Quay with bots only fighting it out. Bots must head for the enemy
## flag (someone gets within 15 m of an enemy base, or takes a flag) within the time limit.
## CTF_TRACE=1 prints every bot's position and goal every 5 s.
##   godot --headless --path . res://tools/check_ctf_bots.tscn   → "CTF BOTS CHECK OK"
const LIMIT_S := 45.0
var fails := 0
var events: Array = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.flag_event.connect(func(k: String, t: int, n: String) -> void: events.append([k, t, n]))
	menu.set_match_choice(&"quay", Game.MODE_CTF)
	for b in menu._bot_boxes:
		b.value = 5
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and not Game.play_locked():
			break
	var me := Game.player_for_peer(1)
	if me:
		me.global_position = Vector3(0, 0, 0) # out of the way, not on a base
	for tm in 2:
		var bot: Player = null
		for n in get_tree().get_nodes_in_group("player"):
			if n is Player and n.is_bot and n.team_id == tm:
				bot = n
		if bot:
			var nav_map := bot.get_world_3d().navigation_map
			var goal: Vector3 = Game.flags[1 - tm].home
			var path := NavigationServer3D.map_get_path(nav_map, bot.global_position, goal, true)
			var end_d := path[-1].distance_to(goal) if path.size() > 0 else INF
			print("  nav path team %d -> enemy base: %d points, ends %.1f m from it" % [tm, path.size(), end_d])
	var closest := INF
	var t := 0.0
	while t < LIMIT_S and events.filter(func(e): return e[0] == "taken").is_empty():
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Player
			if OS.has_environment("CTF_TRACE") and p and p.is_bot and int(t * 2) % 10 == 0:
				print("    t%.0f bot %d team %d pos %s goal %s dead %s" % [t, p.peer_id, p.team_id, str(p.global_position.round()), str(CTF.bot_goal(Game, p).round()), p.is_dead])
			if p and p.is_bot and not p.is_dead:
				closest = minf(closest, p.global_position.distance_to(Game.flags[1 - p.team_id].home))
	print("  closest bot to an enemy flag base: %.1f m, events %s after %.0f s" % [closest, str(events), t])
	_ok(closest < 15.0 or not events.is_empty(), "bots go for the enemy flag (reach its roof)")
	print("CTF BOTS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
