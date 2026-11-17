extends Node
## Renders the pause menu to /tmp/pause_tdm.png and /tmp/pause_ffa.png (needs a display).

func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.33, 0.37)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var pause: Control = (load("res://scenes/pause.tscn") as PackedScene).instantiate()
	layer.add_child(pause)
	Game.scores.clear()
	Game.scores[1] = {"name": "You", "kills": 9, "team": 0, "style": 0, "deaths": 4}
	Game.scores[-1] = {"name": "Bot 1", "kills": 12, "team": 1, "style": 0, "deaths": 6}
	Game.team_kills = [14, 11]
	for m in [[Game.MODE_TDM, "tdm"], [Game.MODE_FFA, "ffa"]]:
		Game.mode = m[0]
		pause.open()
		get_tree().paused = false
		await get_tree().create_timer(0.4).timeout
		await _grab("/tmp/pause_%s.png" % m[1])
	pause._show_settings()
	await get_tree().create_timer(0.4).timeout
	await _grab("/tmp/pause_settings.png")
	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
