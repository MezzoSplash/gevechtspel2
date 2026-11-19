extends Node
## UI crystal step 5: the layout pieces (wordmark, button hints, red leave seams, staggered widths,
## pause score shards, settings page title + tab row, diamond grabber, kill feed shards).
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	CrystalTheme.install()
	_check_pieces()
	await _check_pause()
	await _check_settings()
	await _check_feed()
	await _check_scoreboard()
	await _check_class_select()
	await _check_hud_leftovers()
	print("CRYSTAL LAYOUT CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _check_pieces() -> void:
	print("-- pieces")
	var pts := CrystalMark.points(Vector2(72, 102))
	var inside := true
	for p in pts:
		inside = inside and p.x >= -0.01 and p.y >= -0.01 and p.x <= 72.01 and p.y <= 102.01
	_ok(pts.size() == 7 and inside, "the mark's gem has 7 points inside its box")
	var d := CrystalTheme.diamond(18, Color.WHITE).get_image()
	_ok(d.get_pixel(9, 9).a > 0.99 and d.get_pixel(0, 0).a < 0.01, "diamond grabber: solid centre, clear corner")
	var t := CrystalTheme.install()
	_ok(t.get_icon("grabber", "HSlider").get_width() == 18, "the theme's slider grabber is the diamond")
	var b := Button.new()
	b.theme = t
	b.theme_type_variation = &"MenuButtonBig"
	add_child(b)
	CrystalUi.seam_color(b, CrystalUi.DANGER)
	var red := true
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := b.get_theme_stylebox(st) as CrystalStyle
		red = red and sb != null and is_equal_approx(sb.seam_color.r, CrystalUi.DANGER.r)
	_ok(red, "a leave button's seam is red in every state")
	var shared := t.get_stylebox("hover", "MenuButtonBig") as CrystalStyle
	_ok(not is_equal_approx(shared.seam_color.r, CrystalUi.DANGER.r), "the theme's own shard stays ice")
	var hint := CrystalUi.button_hint(b, "ESC")
	_ok(hint.get_parent() == b and hint.mouse_filter == Control.MOUSE_FILTER_IGNORE, "a button hint is a click-through child")
	var b2 := Button.new()
	add_child(b2)
	CrystalUi.stagger([b, b2], [400, 300])
	_ok(b.custom_minimum_size.x == 400 and b2.custom_minimum_size.x == 300, "stagger sets unequal widths")
	_ok(CrystalUi.wordmark().get_child_count() == 2, "wordmark is mark + words")
	b.queue_free()
	b2.queue_free()


func _check_pause() -> void:
	print("-- pause")
	var pause: Control = (load("res://scenes/pause.tscn") as PackedScene).instantiate()
	add_child(pause)
	await get_tree().process_frame
	Game.scores.clear()
	Game.scores[multiplayer.get_unique_id()] = {"name": "You", "kills": 9, "team": 0, "style": 0, "deaths": 0}
	Game.scores[-1] = {"name": "Bot", "kills": 12, "team": 1, "style": 0, "deaths": 0}
	Game.team_kills = [14, 11]
	Game.mode = Game.MODE_TDM
	pause.refresh_score()
	_ok(_num(pause._score_left) == "14" and _num(pause._score_right) == "11", "TDM: the team scores")
	var sb := pause._score_left.get_theme_stylebox("panel") as CrystalStyle
	_ok(sb.seam_color == Player.team_color(0), "TDM: team colour on the seam")
	Game.mode = Game.MODE_FFA
	pause.refresh_score()
	_ok(_num(pause._score_left) == "9" and _num(pause._score_right) == "12", "FFA: you against the leader")
	var leave := pause.get_node("Center/Buttons/LeaveButton") as Button
	_ok(is_equal_approx((leave.get_theme_stylebox("hover") as CrystalStyle).seam_color.r, CrystalUi.DANGER.r), "pause: leave has the red seam")
	pause._show_settings()
	_ok(not pause._footer.visible, "pause: the key footer hides behind settings")
	pause._show_buttons()
	_ok(pause._footer.visible, "pause: and comes back with the buttons")
	Game.mode = Game.MODE_TDM
	Game.scores.clear()
	Game.team_kills = [0, 0]
	pause.queue_free()
	await get_tree().process_frame


func _num(p: PanelContainer) -> String:
	return (p.get_node("Col/Num") as Label).text


func _check_settings() -> void:
	print("-- settings")
	var panel: Node = (load("res://scenes/settings_panel.tscn") as PackedScene).instantiate()
	add_child(panel)
	await get_tree().process_frame
	var tabs := panel.get_node("Body/Tabs") as HBoxContainer
	_ok(tabs != null and tabs.get_child_count() == panel._TABS.size(), "the six tabs are one row")
	panel.show_tab(3)
	_ok(panel._page_title.text == String(panel._TABS[3]).to_upper(), "the page title follows the tab")
	var row_w := tabs.get_combined_minimum_size().x
	_ok(row_w <= 500.0, "the tab row fits the 500 px column (%d)" % row_w)
	panel.queue_free()
	await get_tree().process_frame


func _check_feed() -> void:
	print("-- kill feed")
	var feed := KillFeed.new()
	feed.size = Vector2(400, 300)
	add_child(feed)
	feed.add_kill("A", "B", &"rifle", 0, 1, "NOSCOPE")
	await get_tree().process_frame
	await get_tree().process_frame
	var row := feed.get_child(0) as HBoxContainer
	_ok(row.get_child_count() == 4 and row.get_child(1) is TextureRect, "a row is still killer, icon, victim, tag")
	_ok(row.draw.get_connections().size() > 0, "the row draws its own shard")
	feed.queue_free()


## #312: the Tab board, the winner card and the style king are crystal shards, not flat boxes.
func _check_scoreboard() -> void:
	print("-- scoreboard")
	for path in ["res://scripts/hud/scoreboard_view.gd", "res://scripts/class_select.gd"]:
		_ok(not FileAccess.get_file_as_string(path).contains("StyleBoxFlat"), "%s builds no flat boxes" % path.get_file())
	Game.scores.clear()
	Game.scores[1] = {"name": "Me", "kills": 9, "team": 0, "style": 120, "deaths": 2}
	Game.scores[-1] = {"name": "Bot", "kills": 4, "team": 1, "style": 0, "deaths": 5}
	Game.team_kills = [10, 5]
	Game.mode = Game.MODE_TDM
	var scores := Game.get_scores()
	var board := ScoreboardView.build(scores, false, 1)
	add_child(board)
	await get_tree().process_frame
	var all_crystal := true
	for n in _all(board):
		var c := n as Control
		if c is PanelContainer:
			all_crystal = all_crystal and c.get_theme_stylebox("panel") is CrystalStyle
	_ok(all_crystal, "every piece of the board is a CrystalStyle shard")
	var teams := board.get_child(1)
	for t in [Game.TEAM_A, Game.TEAM_B]:
		var sb := (teams.get_child(t) as PanelContainer).get_theme_stylebox("panel") as CrystalStyle
		_ok(sb.seam_side == CrystalStyle.Side.TOP and sb.seam_color == Player.team_color(t), "team %d: its colour on the seam" % t)
		_ok(is_equal_approx(sb.seam_lit, ScoreboardView.progress(Game.team_score(t))), "team %d: the lit seam is the score (%.2f)" % [t, sb.seam_lit])
	var me := board.find_child("Me", true, false) as PanelContainer
	_ok(me != null and (me.get_theme_stylebox("panel") as CrystalStyle).pale, "your own row is pale shell")
	board.queue_free()
	var hud: Control = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	hud.set_process(false)
	hud._local_peer_id = 1
	await get_tree().process_frame
	hud._on_round_ended(Game.TEAM_A, "Blue", {})
	var card := hud.scoreboard_container.get_node("WinnerCard") as PanelContainer
	var csb := card.get_theme_stylebox("panel") as CrystalStyle
	_ok(csb != null and csb.seam_color == Player.team_color(Game.TEAM_A), "winner card: a shard with the team colour on its seam")
	var king := hud.scoreboard_container.get_node("StyleKing") as Label
	_ok(king.get_theme_stylebox("normal") is CrystalStyle and hud.style_king_text().begins_with("STYLE KING"), "style king: a shard")
	Game.mode = Game.MODE_FFA
	hud._on_round_ended(1, "Me", {})
	_ok((card.get_theme_stylebox("panel") as CrystalStyle).pale, "FFA, you win: the card is pale shell")
	hud.queue_free()
	Game.mode = Game.MODE_TDM
	Game.scores.clear()
	Game.team_kills = [0, 0]
	await get_tree().process_frame


## #313: the in-game class picker uses the crystal theme, and a long loadout never runs into the name.
func _check_class_select() -> void:
	print("-- class select")
	var cs := ClassSelect.new()
	add_child(cs)
	await get_tree().process_frame
	cs.open_initial()
	await get_tree().process_frame
	_ok(cs.theme == CrystalTheme.install(), "the picker carries the crystal theme")
	var shards := true
	var fits := true
	for b in cs._buttons:
		shards = shards and b.theme_type_variation == &"MenuButtonBig" and not b.has_theme_stylebox_override("hover")
		var hint := b.get_node("Hint") as Label
		fits = fits and b.custom_minimum_size.x >= b.get_minimum_size().x + hint.get_minimum_size().x
	_ok(cs._buttons.size() == Game.loadouts.classes.size() and shards, "one MenuButtonBig shard per class, theme states kept")
	_ok(fits, "every class shard is wide enough for name + loadout")
	var sb := cs._sub.get_theme_stylebox("normal") as CrystalStyle
	_ok(sb.seam_side == CrystalStyle.Side.BOTTOM and sb.seam_lit > 0.95, "countdown: a (near) full seam at the start")
	cs.time_left = 2.0
	cs._refresh_sub()
	_ok(is_equal_approx(sb.seam_lit, 0.2) and sb.seam_color == CrystalUi.DANGER, "countdown: the seam runs out and turns red in the last 3 s")
	cs.close_silently()
	cs.open_change()
	await get_tree().process_frame
	_ok(cs._back.visible and sb.seam_side == CrystalStyle.Side.NONE, "change class: Back shows, no countdown seam")
	cs.close_silently()
	cs.queue_free()
	await get_tree().process_frame


## #314: the last flat HUD pieces. The HUD builds no StyleBoxFlat at all any more; the death report,
## the streak pips and the combo timer are shards, and the combo seam is the time left.
func _check_hud_leftovers() -> void:
	print("-- HUD leftovers")
	var flat := []
	var files := ["res://scripts/hud.gd"]
	for f in DirAccess.get_files_at("res://scripts/hud"):
		if f.ends_with(".gd"):
			files.append("res://scripts/hud/" + f)
	for path in files:
		if FileAccess.get_file_as_string(path).contains("StyleBoxFlat.new()"):
			flat.append(path.get_file())
	_ok(flat.is_empty(), "the HUD builds no flat boxes %s" % [flat])
	var hud: Control = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	hud.set_process(false)
	await get_tree().process_frame
	hud.show_death_report("Bot 8", 124, 5, 63, 3, 37, "rifle")
	var dsb := hud._death_report.get_theme_stylebox("panel") as CrystalStyle
	_ok(dsb != null and dsb.seam_side == CrystalStyle.Side.TOP and dsb.seam_color == CrystalUi.DANGER, "death report: a shard with a red seam")
	var pips_ok: bool = hud.streaks.pips != null and hud.streaks.pips.get_child_count() == Game.LOS_AT
	if pips_ok:
		for pip in hud.streaks.pips.get_children():
			pips_ok = pips_ok and (pip as Panel).get_theme_stylebox("panel") is CrystalStyle
	_ok(pips_ok, "streak pips: one shard per kill up to LOS")
	hud.streaks.n = 2
	hud.streaks.refresh()
	var p0 := (hud.streaks.pips.get_child(0) as Panel).get_theme_stylebox("panel") as CrystalStyle
	var p5 := (hud.streaks.pips.get_child(5) as Panel).get_theme_stylebox("panel") as CrystalStyle
	_ok(p0.fill == hud.HUD_ACCENT and p5.fill != hud.HUD_ACCENT, "streak pips: the kills so far are lit")
	var cm := ComboMeter.new()
	add_child(cm)
	cm.on_combo_changed(120, 1.5, Combo.TIME, "WALLRUN", "build", 0)
	_ok(cm.fill is CrystalStyle and is_equal_approx(cm.fill.seam_lit, 1.0), "combo: a full seam on a fresh combo")
	cm.tick(Combo.TIME * 0.5)
	_ok(is_equal_approx(cm.fill.seam_lit, 0.5), "combo: the seam is the time left (%.2f)" % cm.fill.seam_lit)
	cm.queue_free()
	hud.queue_free()
	await get_tree().process_frame


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
