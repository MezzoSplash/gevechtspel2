extends Node
## #87-#90 headless: RC-XD kills earn style, the best-trickshot killcam keeps the right kill,
## surfing holds the combo timer, and bot difficulty (easy/medium/hard) is wired through.
##   godot --headless res://tools/check_fix_87_90.tscn   → "FIX 87-90 CHECK OK"
var fails := 0
var events: Array = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _style() -> int:
	return int(Game.scores[1].get("style", 0))


func _ready() -> void:
	# #90 pure checks first.
	_ok(Game.parse_bot_difficulty("easy") == Game.BOT_EASY and Game.parse_bot_difficulty("Medium") == Game.BOT_MEDIUM
		and Game.parse_bot_difficulty("hard") == Game.BOT_HARD and Game.parse_bot_difficulty("x") == -1, "parse easy/medium/hard")
	var h: Dictionary = Game.BOT_PROFILES[Game.BOT_HARD]
	_ok(is_equal_approx(h.acquire, BotBrain.ACQUIRE) and is_equal_approx(h.wobble, 1.0) and is_equal_approx(h.track, BotBrain.AIM_TRACK)
		and is_equal_approx(h.pause, 1.0) and is_equal_approx(h.nade, 1.0) and is_equal_approx(h.streak, BotBrain.STREAK_USE_DELAY), "hard = the v0.4.1 bots")
	var e: Dictionary = Game.BOT_PROFILES[Game.BOT_EASY]
	var m: Dictionary = Game.BOT_PROFILES[Game.BOT_MEDIUM]
	_ok(e.acquire > m.acquire and m.acquire > h.acquire, "reaction: easy slower than medium slower than hard")
	_ok(e.wobble > m.wobble and m.wobble > h.wobble, "aim wobble: easy > medium > hard")
	_ok(e.track < m.track and m.track < h.track, "aim tracking: easy < medium < hard")
	_ok(e.pause > m.pause and m.pause > h.pause, "burst pauses: easy > medium > hard")
	var cfg := ConfigFile.new()
	_ok(int(cfg.get_value("match", "bot_difficulty", Game.BOT_MEDIUM)) == Game.BOT_MEDIUM, "default is medium")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	_ok(menu._skill_opts.size() == 2, "Bot skill picker on Solo and Host (%d)" % menu._skill_opts.size())
	var old_skill: int = Game.last_bot_difficulty
	menu._skill_opts[1].select(Game.BOT_EASY)
	menu._skill_opts[1].item_selected.emit(Game.BOT_EASY)
	_ok(menu._skill_opts[0].selected == Game.BOT_EASY and Game.bot_difficulty == Game.BOT_EASY, "Host picker syncs Solo and sets easy")
	menu._skill_opts[0].select(Game.BOT_HARD)
	menu._skill_opts[0].item_selected.emit(Game.BOT_HARD)
	_ok(Game.bot_difficulty == Game.BOT_HARD and is_equal_approx(Game.bot_profile().acquire, BotBrain.ACQUIRE), "Solo picker sets hard")
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
	Game.combo_changed.connect(func(p: int, mu: float, t: float, l: String, st: String, b: int) -> void: events.append([p, mu, t, l, st, b]))
	await get_tree().create_timer(1.0).timeout
	Game._combos.clear()
	var bot := -1
	for id in Game.scores:
		if int(id) < 0:
			bot = int(id)

	# #87 RC-XD
	_ok(Style.detect({"weapon": &"rcxd"}).has(Style.RCXD), "RC-XD kill is a trick")
	_ok(Style.detect({"weapon": &"grenade"}).is_empty(), "grenade still none")
	var s0 := _style()
	Game.register_kill(1, bot, &"rcxd", false)
	_ok(_style() - s0 == int(Style.POINTS[Style.RCXD]), "RC-XD kill: +%d style (%d)" % [Style.POINTS[Style.RCXD], _style() - s0])

	# #88 best trick tags include the combo, and the pick carries the points
	Game.best_trick.clear()
	Game._combos.clear()
	Game.combo_move(1, Combo.WALLRUN)
	Game.combo_move(1, Combo.WALLJUMP)
	Game.register_kill(1, bot, &"rifle", false)
	_ok(str(Game.best_trick.get("tags", "")).contains("COMBO") and int(Game.best_trick.get("pts", 0)) >= 210,
		"combo-landing best: tags '%s', %d pts" % [Game.best_trick.get("tags", ""), Game.best_trick.get("pts", 0)])
	_ok(int(Game.killcam_pick().get("pts", 0)) == int(Game.best_trick.pts), "killcam pick carries the points")
	# #88 killcam: stale waits expire, a death recorded first still matches
	var kc = Game.killcam
	kc._trick_deaths.clear()
	kc.note_trick(9001, 777)
	kc._clock += kc.TRICK_WAIT_MAX + 0.5
	kc.note_death(777)
	_ok(kc._trick_deaths.filter(func(td: Array) -> bool: return int(td[0]) == 9001).is_empty(), "stale best-trick wait does not grab a later death")
	kc.note_death(778)
	kc.note_trick(9002, 778)
	_ok(not kc._trick_deaths.filter(func(td: Array) -> bool: return int(td[0]) == 9002).is_empty(), "death recorded just before the trick still matches")
	kc.note_trick(9003, 779)
	kc.note_trick(9004, 780)
	kc.note_death(779)
	_ok(kc._trick_deaths.filter(func(td: Array) -> bool: return int(td[0]) == 9003).is_empty(), "a superseded best does not take a later death")
	kc._trick_deaths.clear()

	# #89 surf freeze
	events.clear()
	Game._combos.clear()
	Game.combo_move(1, Combo.SLIDE)
	var t_end := Time.get_ticks_msec() + int(Combo.TIME * 1500)
	while Time.get_ticks_msec() < t_end:
		me._style_in_air = true
		me._surf_seen_t = me._style_clock
		await get_tree().process_frame
	_ok(Combo.active(Game.combo_of(1)), "combo alive after 1.5× TIME of surfing")
	_ok(events.any(func(ev: Array) -> bool: return ev[4] == "frozen"), "server sent 'frozen'")
	_ok(hud.combo_meter.frozen and hud.combo_meter.fill.bg_color == ComboMeter.FROZEN_COLOR, "HUD bar shows frozen")
	var left := float(Game.combo_of(1).t)
	_ok(left > Combo.TIME * 0.8, "timer held (%.2f s left)" % left)
	me._style_in_air = false
	me._surf_seen_t = -100.0
	await get_tree().create_timer(0.3).timeout
	_ok(not hud.combo_meter.frozen and float(Game.combo_of(1).get("t", 0.0)) < left, "off the ramp: timer runs again")
	await get_tree().create_timer(Combo.TIME + 0.3).timeout
	_ok(Game.combo_of(1).is_empty(), "then bails as normal")

	Game.remember_match_choice(Game.last_map, Game.last_mode, -1, -1, -1, old_skill)
	print("FIX 87-90 CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)
