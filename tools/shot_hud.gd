extends Node
## Renders HUD parts with sample data to /tmp/hud-*.png (needs a display, e.g. xvfb-run).
## Also the speed meter at sprint, surf and wallrun speed (/tmp/hud-speed-*.png).
## scoreboard, streak (left column), weapons + health (bottom), class select.

var hud: Control


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.42, 0.48)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	layer.add_child(hud)
	Game.scores.clear()
	for r in [
		[1, "Gianni", 0, 14, 6, 320], [-1, "Bot 1", 0, 9, 8, 0], [-2, "Bot 2", 0, 5, 10, 0],
		[7, "Snommel", 1, 12, 9, 150], [-4, "Bot 4", 1, 8, 9, 0], [-5, "Bot 5", 1, 6, 11, 40],
	]:
		Game.scores[r[0]] = {"name": r[1], "kills": r[3], "team": r[2], "style": r[5], "deaths": r[4]}
		Game.pings[r[0]] = 24 if r[0] > 0 else -1
	Game.team_kills = [28, 27]
	hud._local_peer_id = 1
	await get_tree().process_frame
	hud.set_process(false)
	hud.streaks.sel = 1
	hud.set_streak(4, Game.CHARGE_RADAR, Game.CHARGE_RADAR)
	hud.streaks.sel = 0
	hud._refresh_streak_ui()
	hud.set_weapon_slots(PackedStringArray(["Slug Shotgun", "Revolver"]))
	hud.set_weapon_index(0)
	hud.set_ammo(24, 30)
	hud.set_grenades(2, 3)
	hud._on_health(64.0, 100.0)
	var img := await _frame()
	_save(img, "/tmp/hud-full.png", Rect2i())
	_save(img, "/tmp/hud-streak.png", Rect2i(0, 230, 360, 460))
	_save(img, "/tmp/hud-weapons.png", Rect2i(560, 820, 800, 260))
	# Speed meter: sprint (no state), a surf past carry, and a wallrun.
	hud.speed_meter.visible = true
	for shot in [[11.4, "", "sprint"], [21.0, "SURF", "surf"], [14.0, "WALLRUN", "wallrun"]]:
		for i in 90:
			hud.speed_meter.show_speed(shot[0], shot[1], 1.0 / 60.0)
		img = await _frame()
		# Crop scales with the real window: a desktop may hand out its own size instead of 1080p.
		var k := img.get_height() / 1080.0
		_save(img, "/tmp/hud-speed-%s.png" % shot[2], Rect2i(Vector2i(Vector2(560, 760) * k), Vector2i(Vector2(800, 320) * k)))
	# Combo meter halfway through its timer (#314: the timer is the shard's seam), then in the red.
	hud.speed_meter.visible = false
	hud._on_combo_changed(240, 2.0, Combo.TIME, "WALLRUN > DIVE > ROLL", "build", 0)
	hud.combo_meter.tick(Combo.TIME * 0.5)
	img = await _frame()
	var kc := img.get_height() / 1080.0
	_save(img, "/tmp/hud-combo.png", Rect2i(Vector2i(Vector2(560, 620) * kc), Vector2i(Vector2(800, 200) * kc)))
	hud.combo_meter.tick(Combo.TIME * 0.5 - Combo.WARN * 0.5)
	img = await _frame()
	_save(img, "/tmp/hud-combo-warn.png", Rect2i(Vector2i(Vector2(560, 620) * kc), Vector2i(Vector2(800, 200) * kc)))
	hud.combo_meter.reset()
	hud.speed_meter.visible = true
	# Kill feed rows: one you are in, two between others, one with a trick tag.
	hud._local_peer_id = 1
	hud.kill_feed.add_kill("Bot 2", "Snommel", &"shotgun", 0, 1)
	hud.kill_feed.add_kill("Snommel", "Bot 1", &"sniper", 1, 0, "NOSCOPE")
	hud.kill_feed.add_kill("Gianni", "Bot 4", &"rifle", 0, 1)
	img = await _frame()
	var kk := img.get_height() / 1080.0
	_save(img, "/tmp/hud-killfeed.png", Rect2i(Vector2i(Vector2(1400, 40) * kk), Vector2i(Vector2(520, 260) * kk)))
	hud._on_health(22.0, 100.0)
	hud.set_weapon_index(2)
	img = await _frame()
	_save(img, "/tmp/hud-health-low.png", Rect2i(560, 820, 800, 260))
	hud._scoreboard_open = true
	hud.scoreboard_container.visible = true
	hud._refresh_scoreboard()
	img = await _frame()
	_save(img, "/tmp/hud-scoreboard.png", Rect2i())
	hud.scoreboard_container.visible = false
	var cs := ClassSelect.new()
	layer.add_child(cs)
	await get_tree().process_frame
	cs.open_initial()
	img = await _frame()
	_save(img, "/tmp/hud-class-select.png", Rect2i())
	get_tree().quit()


func _frame() -> Image:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _save(img: Image, path: String, crop: Rect2i) -> void:
	var out := img if crop.size == Vector2i.ZERO else img.get_region(crop)
	out.save_png(path)
	print("saved ", path, " ", img.get_size())
