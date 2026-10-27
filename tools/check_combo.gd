extends Node
## #84 headless: combos land on a kill (points × multiplier, once), bail on timeout and on death,
## refresh on each move, repeats are worth less, and the HUD meter follows.
##   godot --headless res://tools/check_combo.tscn   → "COMBO CHECK OK"
var fails := 0
var events: Array = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _style() -> int:
	return int(Game.scores[1].get("style", 0))


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_STYLE_FFA)
	for b in menu._bot_boxes:
		b.value = 1
	for b in menu._kill_boxes:
		b.value = 50
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and not Game.play_locked() and Game.player_for_peer(1):
			break
	var me := Game.player_for_peer(1)
	me._spawn_protect = 999.0
	var hud = main.get_node("CanvasLayer/Hud")
	Game.combo_changed.connect(func(p: int, m: float, t: float, l: String, st: String, b: int) -> void: events.append([p, m, t, l, st, b]))
	await get_tree().create_timer(1.0).timeout # let movement from the spawn settle
	Game._combos.clear()
	var bot := -1
	for id in Game.scores:
		if int(id) < 0:
			bot = int(id)

	# No combo: a plain kill and plain moves bank nothing.
	var s0 := _style()
	Game.register_kill(1, bot, &"rifle", false)
	_ok(_style() == s0, "plain kill without tricks or combo: no style")

	# Land: WALLRUN 60 + WALL JUMP 80 = 140, ×1.5 = 210.
	events.clear()
	s0 = _style()
	Game.combo_move(1, Combo.WALLRUN)
	Game.combo_move(1, Combo.WALLJUMP)
	_ok(_style() == s0, "moves alone bank nothing")
	var c := Game.combo_of(1)
	_ok(int(c.pts) == 140 and is_equal_approx(float(c.mult), 1.5), "combo 140 ×1.5")
	await get_tree().process_frame
	_ok(hud._combo_box and hud._combo_box.visible and hud._combo_total.text.begins_with("140"), "HUD meter shows the combo (%s)" % (hud._combo_total.text if hud._combo_box else "-"))
	Game.register_kill(1, bot, &"rifle", false)
	_ok(_style() - s0 == 210, "kill lands it: +210 (%d)" % (_style() - s0))
	_ok(not events.is_empty() and events[-1][4] == "landed" and int(events[-1][5]) == 210, "LANDED event with 210")
	_ok(Game.combo_of(1).is_empty(), "combo cleared after landing")
	Game.register_kill(1, bot, &"rifle", false)
	_ok(_style() - s0 == 210, "a second kill does not land it again")

	# Refresh: each move refills the bar.
	Game.combo_move(1, Combo.SLIDE)
	await get_tree().create_timer(Combo.TIME * 0.7).timeout
	Game.combo_move(1, Combo.DIVE)
	await get_tree().create_timer(Combo.TIME * 0.7).timeout
	_ok(Combo.active(Game.combo_of(1)), "refreshed by a new move (still alive after 1.4× TIME)")
	_ok(hud._combo_fill.bg_color != hud.COMBO_WARN_COLOR, "bar not red yet")
	await get_tree().create_timer(Combo.TIME * 0.3 - Combo.WARN * 0.5).timeout
	_ok(hud._combo_fill.bg_color == hud.COMBO_WARN_COLOR, "bar turns red near expiry")

	# Bail on timeout.
	events.clear()
	s0 = _style()
	await get_tree().create_timer(Combo.WARN + 0.3).timeout
	_ok(Game.combo_of(1).is_empty() and not events.is_empty() and events[-1][4] == "bailed", "BAILED on timeout")
	_ok(_style() == s0 and hud._combo_total.text == "BAILED", "bail banks nothing, HUD says BAILED")

	# Bail on death.
	events.clear()
	Game.combo_move(1, Combo.SURF)
	Game.combo_move(1, Combo.AIR)
	s0 = _style()
	Game.register_kill(bot, 1, &"rifle", false)
	_ok(Game.combo_of(1).is_empty() and not events.is_empty() and events[-1][4] == "bailed", "BAILED on death")
	_ok(_style() == s0, "death banks nothing")

	# Repeats are worth half and add no multiplier.
	Game._combos.clear()
	Game.combo_move(1, Combo.WALLRUN)
	Game.combo_move(1, Combo.WALLRUN)
	c = Game.combo_of(1)
	_ok(int(c.pts) == 90 and is_equal_approx(float(c.mult), 1.0), "repeat: 60 + 30, ×1.0")
	# Kill tricks + combo in one award (TDM chain multiplier only on the kill tricks).
	var tr := Style.detect({"weapon": &"sniper", "scoped": false})
	_ok(tr.has(Style.NOSCOPE), "kill tricks still detected")
	print("COMBO CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)
