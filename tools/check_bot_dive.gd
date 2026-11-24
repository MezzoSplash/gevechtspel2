extends Node
## #371: a bot's dive has to end on landing. Before this, bots never ran Movement.tick_dive_roll, so
## _diving stayed true from a bot's first dive until it respawned; PawnBody.update_stance keeps crouch = 1
## for a diving pawn, so that bot walked around crouched (measured: one bot at 97-100% on the server).
## This runs a short bot match and fails when any bot is still diving while standing on the floor.
##   godot --headless --fixed-fps 60 res://tools/check_bot_dive.tscn
const BOTS := 6
const TICKS := 2400 # 40 s: a bot only dives when a target is below, so the match needs room
const MAX_DIVE_TICKS := 90 # 1.5 s: a dive that has landed must be closed by then
const PARK := Vector3(0, 400, 0)


func _box(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	s.shape = sh
	b.add_child(s)
	get_tree().root.add_child(b)
	b.global_position = pos


func _ready() -> void:
	seed(1)
	NavigationServer3D.map_set_use_async_iterations(get_viewport().world_3d.navigation_map, false)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is NavigationRegion3D:
			NavigationServer3D.region_set_use_async_iterations((n as NavigationRegion3D).get_rid(), false))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"townhouses", Game.MODE_TDM)
	Game.last_bots = BOTS
	Game.bot_count = BOTS
	for b in menu._bot_boxes:
		b.value = BOTS
	for b in menu._ally_boxes:
		b.value = BOTS / 2 - 1
	for b in menu._enemy_boxes:
		b.value = BOTS / 2
	for o in menu._skill_opts:
		o.selected = BotProfiles.HARD
	Game.last_bot_difficulty = BotProfiles.HARD
	menu.play_local_pressed.emit()
	Game.bot_difficulty = BotProfiles.HARD
	var me: Player = null
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not Game.play_locked() and Game._round_active:
			break
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	# The human sits out of the way so the bots fight each other and keep diving.
	_box(PARK + Vector3(0, -0.5, 0), Vector3(6, 1, 6))
	me._spawn_protect = 1.0e9
	await get_tree().physics_frame
	me.global_position = PARK + Vector3(1.2, 0, 0)
	me.velocity = Vector3.ZERO
	var streak: Dictionary = {} # peer -> how many ticks in a row it has been diving on the floor
	var worst: Dictionary = {} # peer -> the longest streak seen
	var dives := 0
	var seen_diving: Dictionary = {}
	for t in TICKS:
		await get_tree().physics_frame
		for p in Game.players():
			if not p.is_bot or p.is_dead:
				continue
			if p._diving and p.is_on_floor():
				streak[p.peer_id] = int(streak.get(p.peer_id, 0)) + 1
				worst[p.peer_id] = maxi(int(worst.get(p.peer_id, 0)), int(streak[p.peer_id]))
			else:
				streak[p.peer_id] = 0
			if p._diving and not seen_diving.has(p.peer_id):
				seen_diving[p.peer_id] = true
				dives += 1
	var fails := 0
	for id in worst:
		if int(worst[id]) > MAX_DIVE_TICKS:
			print("  bot %d: diving on the floor for %d ticks (%.1f s)" % [int(id), int(worst[id]), float(worst[id]) / 60.0])
			fails += 1
	print("BOT DIVE CHECK %s (%d dives from %d bots)" % ["OK" if fails == 0 else "FAIL", dives, Game.players().size()])
	get_tree().quit(0 if fails == 0 else 1)
