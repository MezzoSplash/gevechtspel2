extends Node
## #388 screenshots to /home/gianni/OpenBot/Shared/gevechtspel2-overdrive/ (needs a display, e.g.
## xvfb-run): the streak menu with Overdrive, the HUD countdown, and the glow plus trail on a pawn as
## the other team sees it.
const OUT := "/home/gianni/OpenBot/Shared/gevechtspel2-overdrive"


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(OUT)

	# 1) The menu, where Overdrive is now one of the two 7-kill picks.
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.show_screen("streaks")
	await get_tree().create_timer(0.6).timeout
	await _grab("%s/menu_overdrive.png" % OUT)
	main.queue_free()
	await get_tree().process_frame

	# 2) The HUD countdown, on the real HUD scene.
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.33, 0.39, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var hud: Control = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	layer.add_child(hud)
	Game.scores.clear()
	Game.scores[1] = {"name": "Gianni", "kills": 9, "team": 0, "style": 420, "deaths": 3}
	hud._local_peer_id = 1
	await get_tree().process_frame
	hud.set_streak_choice([&"uav", &"rcxd", &"overdrive"])
	hud.set_streak(7, Game.CHARGE_OVERDRIVE, Game.CHARGE_OVERDRIVE)
	hud.show_overdrive(7.4)
	await _grab("%s/hud_timer.png" % OUT)
	layer.queue_free()

	# 3) The glow and the trail, seen from the other side of the room.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.62)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.0
	add_child(sun)
	_floor()
	var pawn := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	pawn.peer_id = 7
	pawn.is_bot = true # a remote body: the mesh is visible
	pawn.name = "od7"
	add_child(pawn)
	pawn.global_position = Vector3(0, 0.05, 0)
	await get_tree().process_frame
	Game.streak_charges[7] = int(Game.streak_charges.get(7, 0)) | Game.CHARGE_OVERDRIVE
	Game.streak_choices[7] = ["uav", "rcxd", "overdrive"]
	Game.try_activate_streak(7, 2)
	var cam := Camera3D.new()
	cam.fov = 48.0
	add_child(cam)
	cam.global_position = Vector3(4.2, 1.9, 4.6)
	cam.look_at(Vector3(-0.9, 1.0, 0.0))
	cam.current = true
	# Fly the body across the frame so the trail has something to leave behind. Its own physics is off:
	# a remote pawn is pulled toward its network target every tick, which would undo the move.
	pawn.set_physics_process(false)
	for _i in 40:
		pawn.global_position += Vector3(-0.055, 0.0, 0.0)
		await get_tree().process_frame
	await _grab("%s/glow_trail.png" % OUT)
	get_tree().quit()


func _floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	col.shape = box
	body.add_child(col)
	body.position = Vector3(0, -0.5, 0)
	add_child(body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 1, 40)
	mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.14, 0.15, 0.17)
	mesh.material_override = m
	mesh.position = Vector3(0, -0.5, 0)
	add_child(mesh)


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
