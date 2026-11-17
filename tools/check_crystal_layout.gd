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
