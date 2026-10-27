extends Node
## Renders HUD parts with sample data to /tmp/hud-*.png (needs a display, e.g. xvfb-run).
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
	hud._streak_sel = 1
	hud.set_streak(4, Game.CHARGE_RADAR, Game.CHARGE_RADAR)
	hud._streak_sel = 0
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
