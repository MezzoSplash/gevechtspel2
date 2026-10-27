extends Node
## #63: frames during the round-start freeze (grey) and after it (colour) -> /tmp/freeze_*.png.
##   xvfb-run godot --rendering-driver opengl3 res://tools/shot_freeze.tscn
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.bot_count = 4
	menu.set_match_choice(&"quay", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var grey_seen := false
	var shots := 0
	for i in 300:
		await get_tree().create_timer(0.05).timeout
		var a: float = Game.freeze_grade.amount()
		if Game.round_frozen and a > 0.95 and not grey_seen:
			grey_seen = true
			await _grab("/tmp/freeze_grey.png")
		if grey_seen and not Game.round_frozen and a <= 0.0:
			await _grab("/tmp/freeze_colour.png")
			shots = 2
			break
	print("FREEZE GREY CHECK ", "OK" if shots == 2 else "FAILED (grey_seen=%s)" % grey_seen)
	get_tree().quit()


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
