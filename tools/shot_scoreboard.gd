extends Node
## Renders the Tab scoreboard with sample data to /tmp/scoreboard.png (needs a display, e.g. xvfb-run).

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.38, 0.44)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(bg)
	var hud: Control = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	layer.add_child(hud)
	Game.scores.clear()
	var sample := [
		[1, "Gianni", 0, 14, 6, 320], [-1, "Bot 1", 0, 9, 8, 0], [-2, "Bot 2", 0, 5, 10, 0],
		[-3, "Bot 3", 0, 3, 7, 0], [7, "Snommel", 1, 12, 9, 150], [-4, "Bot 4", 1, 8, 9, 0],
		[-5, "Bot 5", 1, 6, 11, 40], [-6, "Bot 6", 1, 2, 12, 0],
	]
	for r in sample:
		Game.scores[r[0]] = {"name": r[1], "kills": r[3], "team": r[2], "style": r[5], "deaths": r[4]}
		Game.pings[r[0]] = 24 if r[0] > 0 else -1
	Game.team_kills = [31, 28]
	hud._local_peer_id = 1
	hud.set_process(false)
	await get_tree().process_frame
	hud._scoreboard_open = true
	hud.scoreboard_container.visible = true
	hud._refresh_scoreboard()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/scoreboard.png")
	print("saved /tmp/scoreboard.png")
	get_tree().quit()
