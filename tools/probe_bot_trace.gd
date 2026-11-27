extends Node
## Parity probe for bot refactors (not a check; run_checks skips probe_*): a seeded bot-only fight, one
## line per bot per physics tick with position, velocity, yaw, state, HP, kills, gun, death, slide and
## wallrun, so two builds can be diffed. The local human is parked on a slab far above the map with spawn
## protection, out of the fight. Run it through tools/bot_parity.sh (#317: the bot_brain split must leave
## it byte-identical), which gives Godot its own XDG_DATA_HOME: the menu saves every choice made here to
## settings.cfg and would overwrite your own.
##   godot --headless --fixed-fps 60 res://tools/probe_bot_trace.tscn -- OUT [map] [tdm|ffa] [ticks] [skill]
## Defaults: quay, tdm, 3600 ticks (60 s), hard, 8 bots. Deterministic run to run at --fixed-fps 60:
## seed(1), every BotBrain.rng seeded by slot, TDM respawns on fixed team spots, and navigation switched to
## synchronous updates for the run (Godot's default threads them, so the first path landed on a varying
## frame). Not deterministic, so left out of bot_parity.sh: FFA (main.gd spaces FFA spawns by wall-clock
## time) and Skyline (one of two traces, a race while it loads). Easy and Medium used to be excluded too
## because BotBrain's hearing read Time.get_ticks_msec; since #354 it reads simulation time (physics
## frames), so both skills can be traced.
const PARK := Vector3(0, 400, 0)
const BOTS := 8


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
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "/tmp/bot_trace.txt"
	var map_id := StringName(args[1]) if args.size() > 1 else &"quay"
	var mode := Game.MODE_FFA if args.size() > 2 and args[2] == "ffa" else Game.MODE_TDM
	var ticks := int(args[3]) if args.size() > 3 else 3600
	var skill := BotProfiles.parse(args[4]) if args.size() > 4 else BotProfiles.HARD
	if skill < 0:
		skill = BotProfiles.HARD
	seed(1)
	# Godot updates navigation maps and regions on a worker thread by default, so the frame a bot first
	# gets a path varies run to run. Synchronous here: the world's map now, each region as it appears.
	NavigationServer3D.map_set_use_async_iterations(get_viewport().world_3d.navigation_map, false)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is NavigationRegion3D:
			NavigationServer3D.region_set_use_async_iterations((n as NavigationRegion3D).get_rid(), false))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(map_id, mode)
	Game.last_bots = BOTS
	Game.bot_count = BOTS
	for b in menu._bot_boxes:
		b.value = BOTS
	for b in menu._ally_boxes:
		b.value = BOTS / 2 - 1
	for b in menu._enemy_boxes:
		b.value = BOTS / 2
	for o in menu._skill_opts:
		o.selected = skill
	Game.last_bot_difficulty = skill
	Game.bot_difficulty = skill
	menu.play_local_pressed.emit()
	Game.bot_difficulty = skill
	var me: Player = null
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not Game.play_locked() and Game._round_active:
			break
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	_box(PARK + Vector3(0, -0.5, 0), Vector3(6, 1, 6))
	me._spawn_protect = 1.0e9
	await get_tree().physics_frame
	me.global_position = PARK + Vector3(0, 1.2, 0)
	me.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var out: PackedStringArray = []
	out.append("# %s %s %d bots %s" % [map_id, Game.mode_name(), BOTS, BotProfiles.IDS[Game.bot_difficulty]])
	for t in ticks:
		await get_tree().physics_frame
		var bots: Array[Player] = []
		for p in Game.players():
			if p.is_bot:
				bots.append(p)
		bots.sort_custom(func(a: Player, b: Player) -> bool: return a.peer_id > b.peer_id)
		for p in bots:
			var pos := p.global_position
			var v := p.velocity
			var st := int(p._bot_brain.state) if p._bot_brain else -1
			var kills := int(Game.scores.get(p.peer_id, {}).get("kills", 0))
			out.append("%d %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %d %.2f %d %d %d %d %d" % [
				t, p.peer_id, pos.x, pos.y, pos.z, v.x, v.y, v.z, p.rotation.y, st, Game.hp_of(p), kills,
				p.weapon.active_index() if p.weapon else -1, int(p.is_dead), int(p._sliding), int(p._wallrunning)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	print("BOT TRACE: %d lines -> %s" % [out.size(), path])
	get_tree().quit()
