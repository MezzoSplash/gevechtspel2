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
		"overview": [Vector3(44, 40, 60), Vector3(0, 3, 0)],
		"overview_o": [Vector3(-44, 40, -60), Vector3(0, 3, 0)],
		"bunker": [Vector3(-26, 12.0, 38), Vector3(-29, 5, 0)],
		"flank": [Vector3(-20, 2.0, 30), Vector3(-22, 1.5, -20)],
		"hall": [Vector3(0, 2.0, 12.5), Vector3(0, 1.8, -10)],
		"hall_mezz": [Vector3(-9.6, 4.6, 12.5), Vector3(4, 1.0, -4)],
		"furnace_yard": [Vector3(26, 3.0, 34), Vector3(0, 8, 0)],
		"sand_ladle": [Vector3(28, 2.4, -6), Vector3(10, 5, 18)],
		"roof": [Vector3(14, 9.5, 18), Vector3(-4, 6, -6)],
		"yard": [Vector3(20, 3, 28), Vector3(-10, 2, 0)],
		"spawn": [Vector3(0, 2.0, 42), Vector3(0, 2, 10)],
	},
	"townhouses": {
		"overview": [Vector3(42, 40, 62), Vector3(0, 2, 0)],
		"overview_o": [Vector3(-42, 40, -62), Vector3(0, 2, 0)],
		"canal": [Vector3(0, 2.0, 34), Vector3(0, -1.0, 0)],
		"roof": [Vector3(-17, 11.5, 39), Vector3(-12, 5, 0)],
		"quay": [Vector3(9, 2.0, 30), Vector3(6, 1.5, -10)],
		"drawbridge": [Vector3(14, 6, 10), Vector3(0, 6, 0)],
		"alley": [Vector3(-28, 2.0, 30), Vector3(-28, 1.5, -10)],
		"spawn": [Vector3(0, 2.0, 46), Vector3(0, 2, 20)],
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
