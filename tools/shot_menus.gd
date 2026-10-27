extends Node
## Renders the main menu screens to /tmp/menu_*.png (needs a display, e.g. xvfb-run).

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	await _grab("/tmp/menu_home.png")
	for id in ["settings", "solo", "mp"]:
		menu.show_screen(id)
		await get_tree().create_timer(0.5).timeout
		await _grab("/tmp/menu_%s.png" % id)
	menu.set_mp_tab(0)
	await get_tree().create_timer(0.5).timeout
	await _grab("/tmp/menu_mp_host.png")
	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
