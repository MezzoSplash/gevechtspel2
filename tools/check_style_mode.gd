extends Node
## #82 headless: style modes parse, limits, leader by style, round ends on the style limit (FFA and TDM),
## kills alone never end a style round, HUD/menu wording.
##   godot --headless res://tools/check_style_mode.tscn   → "STYLE MODE CHECK OK"
var fails := 0
var ended: Array = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	_ok(Game.parse_mode("style-tdm") == Game.MODE_STYLE_TDM and Game.parse_mode("style-ffa") == Game.MODE_STYLE_FFA, "parse_mode style-tdm / style-ffa")
	_ok(Game.parse_mode("tdm") == Game.MODE_TDM and Game.parse_mode("ffa") == Game.MODE_FFA, "kill modes unchanged")
	_ok(Game.is_ffa(Game.MODE_STYLE_FFA) and not Game.is_ffa(Game.MODE_STYLE_TDM), "style FFA has no teams")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.round_ended.connect(func(w: int, n: String, _s: Dictionary) -> void: ended.append([w, n]))
	# Menu: picking a style mode relabels the limit row.
	var mo: ChoiceRow = menu._mode_opts[menu._mode_opts.size() - 1]
	_ok(mo.item_count == Game.MODE_NAMES.size(), "Host/Solo mode pickers list every mode")
	mo.select(Game.MODE_STYLE_FFA)
	mo.item_selected.emit(Game.MODE_STYLE_FFA)
	_ok(menu.selected_mode() == Game.MODE_STYLE_FFA, "style FFA selectable")
	var kb: SpinBox = menu._kill_boxes[0]
	_ok(kb.suffix.contains("style") and (kb.get_parent().get_child(0) as Label).text == "Style", "limit row says Style")
	# Limit scales with the round: rate ×100 × minutes. Defaults: FFA 25 000, TDM 40 000 in 10 min.
	_ok(Game.style_limit_for(Game.STYLE_FFA_LIMIT, 600.0) == 25000 and Game.style_limit_for(Game.STYLE_TDM_LIMIT, 600.0) == 40000, "default limits 25 000 / 40 000 for 10 min")
	_ok(Game.style_limit_for(25, 300.0) * 2 == Game.style_limit_for(25, 600.0), "limit doubles with twice the time")
	var big := Combo.fresh()
	for m in [Combo.SLIDE, Combo.DIVE, Combo.ROLL, Combo.WALLRUN, Combo.WALLJUMP, Combo.WALL_TO_WALL, Combo.SURF, Combo.AIR]:
		Combo.add_move(big, m)
	print("  one 8-move combo: %d × %.1f = %d" % [big.pts, big.mult, Combo.value(big)])
	_ok(Combo.value(big) * 4 < Game.style_limit_for(Game.STYLE_FFA_LIMIT, 600.0), "a big combo is under a quarter of the FFA limit (no win in seconds)")
	# #151: kills this life raise the combo factor (Gianni's example: 3 wall jumps 180 -> ~500 at 3 kills).
	var wj := Combo.fresh()
	for i in 3:
		Combo.add_move(wj, Combo.WALLJUMP)
	var wj0 := Combo.value(wj)
	wj["kf"] = Combo.streak_factor(3)
	var wj3 := Combo.value(wj)
	print("  3 wall jumps: %d at 0 kills, %d at 3 kills" % [wj0, wj3])
	_ok(wj0 == 160 and wj3 >= 450 and wj3 <= 550, "#151: 3 kills turn a 160 combo into ~500 (%d)" % wj3)
	_ok(Combo.streak_factor(0) == 1.0 and Combo.streak_factor(99) == Combo.streak_factor(3), "#151: no kills = x1, capped after 3")
	big["kf"] = Combo.streak_factor(99)
	print("  big combo at max streak: %d" % Combo.value(big))
	_ok(Combo.value(big) * 3 < Game.style_limit_for(Game.STYLE_FFA_LIMIT, 600.0), "#151: even at max streak a big combo is under a third of the FFA limit")
	# Style FFA, rate 5 × 1 min (= 500 style), 3 bots.
	for b in menu._time_boxes:
		b.value = 1
	for b in menu._kill_boxes:
		b.value = 5
	for b in menu._bot_boxes:
		b.value = 3
	menu.play_local_pressed.emit()
	await _wait_round()
	_ok(Game.score_limit() == 500 and Game.score_word() == "style", "style limit 500")
	# Kills alone never end it.
	for i in 6:
		Game.register_kill(1, -1, &"rifle", false)
	_ok(ended.is_empty(), "kills do not end a style round")
	# #151 live: the server stamps the killstreak factor on the combo; death resets the streak.
	Game._combos.erase(1)
	Game.combo_move(1, Combo.WALLJUMP)
	_ok(is_equal_approx(float(Game.combo_of(1).get("kf", 0.0)), Combo.streak_factor(int(Game.streak_progress.get(1, 0)))), "#151: combo carries the streak factor (%s)" % Game.combo_of(1).get("kf", "-"))
	Game._combos.erase(1)
	for i in 7:
		Game.award_move_trick(1, Style.WALL_TO_WALL) # 7 × 75 = 525
	await get_tree().process_frame
	_ok(ended.size() == 1 and int(ended[0][0]) == 1, "player reaching 500 style wins (FFA)")
	_ok(Game.top_player() == 1, "leader is the style leader")
	# Style TDM: team totals.
	ended.clear()
	main._reset_match_state()
	menu.set_match_choice(&"quay", Game.MODE_STYLE_TDM)
	# A teammate bot for the team total; ask for one instead of trusting the saved bot split
	# (0 is "no such peer", not -1: a bot peer id can legitimately be -1).
	menu.set_bots_total(3)
	for b in menu._kill_boxes:
		b.value = 5
	menu.play_local_pressed.emit()
	await _wait_round()
	var me := Game.player_for_peer(1)
	var team := me.team_id
	var mate := 0 # 0 = nobody found; bot peer ids are negative, and -1 is a real bot
	for id in Game.scores:
		if int(id) < 0 and int(Game.scores[id].get("team", 0)) == team:
			mate = int(id)
			break
	for i in 4:
		Game.award_move_trick(1, Style.WALL_TO_WALL) # 300
	_ok(Game.team_score(team) == 300 and ended.is_empty(), "team style sums (300), no winner yet")
	if mate != 0:
		for i in 3:
			Game.award_move_trick(mate, Style.WALL_TO_WALL) # +225 from a teammate
	await get_tree().process_frame
	_ok(ended.size() == 1 and int(ended[0][0]) == team, "team reaching 500 style wins (TDM, teammate %d)" % mate)
	print("STYLE MODE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)


func _wait_round() -> void:
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and not Game.play_locked():
			return
