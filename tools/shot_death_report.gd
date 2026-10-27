extends Node
## #64 death report card -> /tmp/death_report.png (xvfb-run godot --rendering-driver opengl3 res://tools/shot_death_report.tscn)
func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.38, 0.44)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var hud: Control = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	layer.add_child(hud)
	await get_tree().process_frame
	hud.set_process(false)
	hud._on_died()
	hud.show_death_report("Bot 8", 124, 5, 63, 3, 37)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().get_region(Rect2i(500, 300, 600, 330)).save_png("/tmp/death_report.png")
	print("saved /tmp/death_report.png")
	get_tree().quit()
