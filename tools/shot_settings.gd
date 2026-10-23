extends Node
## Renders every settings tab to /tmp/settings_<tab>.png (needs a display, e.g. xvfb-run).

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.show_screen("settings")
	var panel = menu.settings_panel
	for i in panel._TABS.size():
		panel.show_tab(i)
		await get_tree().create_timer(0.4).timeout
		await _grab("/tmp/settings_%s.png" % String(panel._TABS[i]).to_lower())
	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
