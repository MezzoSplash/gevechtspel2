extends Node
## Solo FFA on Quay with 12 bots for ~90 s: do bots rotate guns, throw frags, and use UAV / RC-XD?
## Also checks the tension music state machine.
##   godot --headless res://tools/check_bot_kit.tscn

var _deaths := {}
var _guns := {}
var _nades := 0
var _rc := 0
var _radar := 0
var _seen_nades := {}
var _seen_rc := {}

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	var menu_on_in_menu: bool = Game._menu_music.playing and not Game._menu_music.stream_paused
	Game.last_bots = 12
	Game.bot_count = 12
	menu.set_match_choice(&"quay", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	Game.kill_feed.connect(func(_k: String, _v: String, weapon_id: StringName, _a = null, _b = null, _c = null, _d = null) -> void:
		_deaths[weapon_id] = int(_deaths.get(weapon_id, 0)) + 1
	)
	var used := {0: 0, 1: 0}
	Game.streak_used.connect(func(pid: int, slot: int) -> void:
		if pid < 0:
			used[slot] += 1
	)
	var tension_start := false
	var tension_final := false
	for t in 900:
		await get_tree().create_timer(0.1).timeout
		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Player
			if p and p.is_bot and p.weapon and p.weapon.def:
				_guns[p.weapon.def.id] = true
		for g in get_tree().get_nodes_in_group("grenade"):
			if not _seen_nades.has(g):
				_seen_nades[g] = true
				_nades += 1
		for c in get_tree().get_nodes_in_group("rc_xd"):
			if not _seen_rc.has(c):
				_seen_rc[c] = true
				_rc += 1
		if Game.radar_left > 0.0 or Game.radar_peer != 0:
			_radar += 1
		if Game._tension and Game._tension.playing:
			if Game._tension.stream == Game._tension_start_stream:
				tension_start = true
			elif Game._tension.stream == Game._tension_final_stream:
				tension_final = true
	var menu_off_in_match: bool = Game._menu_music.stream_paused
	print("menu music in menu: ", menu_on_in_menu, "  paused in match: ", menu_off_in_match)
	# Leader close to the limit: the final cue must start on its own.
	Game.kill_limit = Game.leader_kills() + 2
	await get_tree().create_timer(0.5).timeout
	tension_final = Game._tension.playing and Game._tension.stream == Game._tension_final_stream
	print("bot guns seen: ", _guns.keys(), " (", _guns.size(), "/", Weapon.LOADOUT.size(), ")")
	print("grenades thrown: ", _nades)
	print("rc-xd launched: ", _rc)
	print("bot streaks used: UAV=%d RC-XD=%d" % [used[0], used[1]])
	var ok: bool = _guns.size() == Weapon.LOADOUT.size() and _nades > 0 and used[0] > 0 and used[1] > 0 and tension_start and tension_final
	print("BOT KIT CHECK ", "OK" if ok else "FAILED")
	print("streak charges now: ", Game.streak_charges)
	print("deaths by weapon: ", _deaths)
	print("tension start cue played: ", tension_start, "  final cue played: ", tension_final,
		"  leader kills=", Game.leader_kills(), "/", Game.win_kills(), " time left=", Game.get_round_time_left())
	get_tree().quit()
