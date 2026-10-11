extends Node

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.ambient_light_energy = 1.1
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.current = true
	add_child(cam)

	var gun_root := Node3D.new()
	add_child(gun_root)
	var model := (load("res://assets/weapons/smg/weapon_smg.tscn") as PackedScene).instantiate() as Node3D
	gun_root.add_child(model)
	Weapon.prepare_muzzle(model)
	var fit: Dictionary = Weapon.fit_model(model, &"smg", Vector3(0.24, -0.18, -0.42))
	gun_root.position = fit.root
	await _grab("/tmp/smg_rest.png")
	Weapon.play_model_shot(model, 1.0, 20.0)
	await get_tree().create_timer(0.03).timeout
	await _grab("/tmp/smg_fire.png")
	gun_root.visible = false

	var car := RcXd.new()
	car.owner_team = 0
	add_child(car)
	cam.position = Vector3(0.0, 0.55, 0.85)
	cam.rotation = Vector3.ZERO
	await _grab("/tmp/rc_cam.png")
	cam.position = Vector3(1.6, 0.7, 1.4)
	cam.look_at(Vector3(0.0, 0.05, 0.0))
	await _grab("/tmp/rc_side.png")
	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())
