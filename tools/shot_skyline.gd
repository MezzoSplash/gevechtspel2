extends Node
## Renders Skyline views to /tmp/skyline_*.png (needs a display, e.g. xvfb-run).

const VIEWS := {
	"overview": [Vector3(46, 40, 66), Vector3(0, 6, 0)],
	"top": [Vector3(0.1, 95, 0), Vector3(0, 0, 0)],
	"spawn_blue": [Vector3(-6, 13.7, 44), Vector3(0, 10, 20)],
	"tower_room": [Vector3(4.5, 7.7, 28), Vector3(-3, 8.5, 22)],
	"mid": [Vector3(-8, 7.7, 8), Vector3(8, 6.5, -8)],
	"west_lane": [Vector3(-24, 10.7, 40), Vector3(-24, 5, 5)],
	"fire_escape": [Vector3(10, 13.7, 39), Vector3(17, 15, 27)],
	"perch": [Vector3(26, 16.7, 35), Vector3(-5, 7, -10)],
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
		get_viewport().get_texture().get_image().save_png("/tmp/skyline_%s.png" % k)
		print("saved ", k)
	get_tree().quit()
