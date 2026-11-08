extends Node
## Renders map views to /tmp/<map>_<view>.png (needs a display, e.g. xvfb-run).
## Map id comes from the user args: `-- --map rooftops`. Default: rooftops.

const VIEWS := {
	"rooftops": {
		"overview": [Vector3(34, 36, 48), Vector3(0, 3, 0)],
		"top": [Vector3(0.1, 95, 0.1), Vector3(0, 0, 0)],
		"court_wide": [Vector3(22, 13, 22), Vector3(-2, 2, -2)],
		"alley": [Vector3(0, 2.4, 11.5), Vector3(0, 2.2, -11)],
		"bridge_w": [Vector3(-13, 8.2, 10), Vector3(-13, 6, -11)],
		"bridge_side": [Vector3(2, 9, 16), Vector3(-13, 6, 0)],
		"spawn_blue": [Vector3(0, 3.6, 39), Vector3(0, 3, 14)],
	},
	"foundry": {
		"overview": [Vector3(38, 40, 44), Vector3(0, 3, 0)],
		"roof": [Vector3(-16, 12.5, 16), Vector3(0, 8, -2)],
		"roof_wall": [Vector3(-6.5, 8.6, 9), Vector3(-4.3, 9.6, -4)],
		"hall": [Vector3(0, 3.0, 9.5), Vector3(-6, 3, -6)],
		"west_yard": [Vector3(-16, 6, 10), Vector3(-18, 1.5, -6)],
	},
	"townhouses": {
		"overview": [Vector3(40, 34, 52), Vector3(0, 2, 0)],
		"plaza": [Vector3(0, 9, 22), Vector3(-10, 2, -4)],
		"alley_w": [Vector3(-15.2, 2.6, 12), Vector3(-15.2, 1.6, -9)],
		"street": [Vector3(0, 2.6, 26), Vector3(0, 2.4, -10)],
	},
}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map := &"rooftops"
	for i in args.size():
		if args[i] == "--map" and i + 1 < args.size():
			map = StringName(args[i + 1])
	var views: Dictionary = VIEWS.get(String(map), {})
	if views.is_empty():
		print("SHOT: no views for map ", map)
		get_tree().quit(1)
		return
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(map, Game.MODE_TDM)
	main._on_menu_match_choice(map, Game.MODE_TDM)
	await get_tree().create_timer(2.0).timeout
	main.get_node("CanvasLayer").visible = false
	var cam := Camera3D.new()
	cam.fov = 80
	cam.far = 700
	add_child(cam)
	cam.current = true
	for k in views:
		var v: Array = views[k]
		cam.global_position = v[0]
		cam.look_at(v[1])
		await get_tree().create_timer(0.4).timeout
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/%s_%s.png" % [map, k])
		print("saved ", k)
	get_tree().quit()
