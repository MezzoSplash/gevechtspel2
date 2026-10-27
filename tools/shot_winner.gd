extends Node
## Round-end winner card over the scoreboard: FFA bot, FFA local win, TDM; to /tmp/winner_*.png (needs a display, e.g. xvfb-run).

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
	for shot in [["ffa_bot", Game.MODE_FFA, -3, "Bot 8"], ["ffa_you", Game.MODE_FFA, 1, "Gianni"], ["tdm", Game.MODE_TDM, 1, "Orange"]]:
		Game.mode = shot[1]
		hud._on_round_ended(shot[2], shot[3], {})
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/winner_%s.png" % shot[0])
		print("saved ", shot[0])
	get_tree().quit()
