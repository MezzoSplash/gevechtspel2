extends Node
## #148 headless: Gun Game mode. Parse + menu, start on the first gun, a gun kill promotes, a knife kill
## demotes the victim, a suicide costs a step, bots carry their step's gun, the HUD names the next gun,
## and a kill with the last gun wins the round.
##   godot --headless --path . res://tools/check_gun_game.tscn   → "GUN GAME CHECK OK"
var fails := 0
var ended: Array = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _gun(peer: int) -> StringName:
	var p := Game.player_for_peer(peer)
	return p.weapon.def.id if p and p.weapon and p.weapon.def else &""


func _ready() -> void:
	_ok(Game.parse_mode("gungame") == Game.MODE_GUN_GAME and Game.parse_mode("gg") == Game.MODE_GUN_GAME, "parse_mode gungame / gg")
	_ok(Game.is_ffa(Game.MODE_GUN_GAME) and Game.is_gun_game(Game.MODE_GUN_GAME), "Gun Game is FFA")
	for id in GunGame.LADDER:
		_ok(Game.weapon_def(id) != null, "ladder gun %s exists" % id)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.round_ended.connect(func(w: int, n: String, _s: Dictionary) -> void: ended.append([w, n]))
	menu.set_match_choice(&"quay", Game.MODE_GUN_GAME)
	_ok(menu.selected_mode() == Game.MODE_GUN_GAME, "Gun Game selectable in the menu")
	_ok(not (menu._kill_boxes[0] as Control).get_parent().visible, "Gun Game hides the Kills limit row")
	for b in menu._bot_boxes:
		b.value = 3
	for b in menu._time_boxes:
		b.value = 10
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and not Game.play_locked() and Game.player_for_peer(1):
			break
	var bots: Array[int] = []
	for id in Game.scores:
		if int(id) < 0:
			bots.append(int(id))
	_ok(bots.size() == 3, "three bots")
	_ok(_gun(1) == GunGame.LADDER[0], "start on %s (%s)" % [GunGame.LADDER[0], _gun(1)])
	_ok(Game.player_for_peer(1).grenades == 0, "no grenades in Gun Game")
	_ok(_gun(bots[0]) == GunGame.LADDER[0], "bot starts on %s (%s)" % [GunGame.LADDER[0], _gun(bots[0])])
	Game.register_kill(1, bots[0], GunGame.LADDER[0], false)
	_ok(GunGame.level_of(Game, 1) == 1 and _gun(1) == GunGame.LADDER[1], "gun kill promotes: %s" % _gun(1))
	_ok(Game.score_word() == "level" and Game.score_limit() == GunGame.LADDER.size(), "scoreboard counts levels")
	Game.register_kill(bots[1], 1, &"melee", false)
	_ok(GunGame.level_of(Game, 1) == 0 and _gun(1) == GunGame.LADDER[0], "knife kill demotes the victim")
	_ok(GunGame.level_of(Game, bots[1]) == 0, "knife kill does not promote the killer")
	Game.register_kill(bots[2], bots[2], &"grenade", false)
	_ok(GunGame.level_of(Game, bots[2]) == 0, "suicide on step 0 stays on 0")
	Game.register_kill(bots[2], bots[0], GunGame.LADDER[0], false)
	await get_tree().create_timer(0.3).timeout
	_ok(_gun(bots[2]) == GunGame.LADDER[1], "bot moves up the ladder (%s)" % _gun(bots[2]))
	_ok(Game.player_for_peer(bots[2]).has_weapon(GunGame.LADDER[1]) and not Game.player_for_peer(bots[2]).has_weapon(GunGame.LADDER[0]), "bot carries only its step's gun")
	Game.register_kill(bots[2], bots[2], &"grenade", false)
	_ok(GunGame.level_of(Game, bots[2]) == 0, "suicide costs a step")
	_ok(GunGame.hud_line(0).contains("next"), "HUD names the next gun (%s)" % GunGame.hud_line(0))
	_ok(GunGame.hud_line(GunGame.LADDER.size() - 1).contains("LAST GUN"), "HUD flags the last gun")
	# Climb to the top; the last gun's kill wins.
	for i in GunGame.LADDER.size() - 1:
		await get_tree().create_timer(0.05).timeout
		Game.register_kill(1, bots[0], GunGame.weapon_at(GunGame.level_of(Game, 1)), false)
	_ok(GunGame.level_of(Game, 1) == GunGame.LADDER.size() - 1 and _gun(1) == GunGame.LADDER[-1], "top step: %s" % _gun(1))
	_ok(ended.is_empty(), "not won before the last kill")
	Game.register_kill(1, bots[1], GunGame.LADDER[-1], false)
	await get_tree().process_frame
	_ok(ended.size() == 1 and int(ended[0][0]) == 1, "a kill with the last gun wins the round")
	print("GUN GAME CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
