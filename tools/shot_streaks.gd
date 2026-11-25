extends Node
## Renders the killstreak screen and the HUD streak column (#387) to /home/gianni/OpenBot/Shared/
## gevechtspel2-streaks/ (needs a display, e.g. xvfb-run). Menu: menu_streaks.png. HUD: hud_streaks.png
## with the default pick and hud_streaks_pick.png with a two-streak pick (RCXplodie, LOS).
const OUT := "/home/gianni/OpenBot/Shared/gevechtspel2-streaks"


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(OUT)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.show_screen("streaks")
	await get_tree().create_timer(0.6).timeout
	await _grab("%s/menu_streaks.png" % OUT)
	menu.show_screen("home")
	main.queue_free()
	await get_tree().process_frame

	# HUD: a live column with the default pick, then a two-streak pick.
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.42, 0.48)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var hud: Control = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	layer.add_child(hud)
	Game.scores.clear()
	for r in [[1, "Gianni", 0, 14, 6, 320], [-1, "Bot 1", 0, 9, 8, 0]]:
		Game.scores[r[0]] = {"name": r[1], "kills": r[3], "team": r[2], "style": r[5], "deaths": r[4]}
	Game.team_kills = [28, 27]
	hud._local_peer_id = 1
	await get_tree().process_frame
	hud.set_process(false)
	hud.set_streak_choice(StreakDefs.default_ids())
	hud.set_streak(4, Game.CHARGE_RADAR, Game.CHARGE_RADAR)
	hud._refresh_streak_ui()
	await _grab("%s/hud_streaks.png" % OUT)
	hud.set_streak_choice([&"rcxd", &"los"])
	hud.set_streak(6, Game.CHARGE_RCXD, Game.CHARGE_RCXD)
	hud._refresh_streak_ui()
	await _grab("%s/hud_streaks_pick.png" % OUT)
	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
