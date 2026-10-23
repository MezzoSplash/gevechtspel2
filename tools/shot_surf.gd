extends Node
## Renders Skyline views to /tmp/skyline_*.png (needs a display, e.g. xvfb-run).

const VIEWS := {
	"overview": [Vector3(-40, 30, 48), Vector3(-12, 7, 12)],
	"entry": [Vector3(-12.5, 13.7, 39), Vector3(-13, 9, 20)],
	"ride": [Vector3(-11.2, 12.2, 27), Vector3(-12, 8, 8)],
	"exit_deck": [Vector3(-6, 7.7, 0), Vector3(-14, 8, 20)],
	"orange": [Vector3(40, 30, -48), Vector3(12, 7, -12)],
}

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"skyline", Game.MODE_TDM)
	main._on_menu_match_choice(&"skyline", Game.MODE_TDM)
	await get_tree().create_timer(2.0).timeout
	main.get_node("CanvasLayer").visible = false
	var cam := Camera3D.new()
	cam.fov = 80
	cam.far = 600
	add_child(cam)
	cam.current = true
	for k in VIEWS:
		var v: Array = VIEWS[k]
		cam.global_position = v[0]
		cam.look_at(v[1])
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/surf_%s.png" % k)
		print("saved ", k)
	get_tree().quit()
