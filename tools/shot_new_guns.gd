extends Node
## Viewmodel shots of the LMG and slug shotgun (and the guns they sit next to) to /tmp/gun_<id>.png.
## Needs a display: xvfb-run godot --rendering-driver opengl3 res://tools/shot_new_guns.tscn

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
	for id in [&"lmg", &"slug", &"shotgun", &"rifle"]:
		var gun_root := Node3D.new()
		add_child(gun_root)
		var model := (Weapon.MODEL_SCENES[id] as PackedScene).instantiate() as Node3D
		gun_root.add_child(model)
		var fit: Dictionary = Weapon.fit_model(model, id, Vector3(0.24, -0.18, -0.42))
		gun_root.position = fit.root
		await _grab("/tmp/gun_%s.png" % id)
		if fit.has("sight_y") and Game.weapon_def(id).ads_fov > 0.0:
			gun_root.position = Vector3(0.0, -float(fit.sight_y) - 0.004, fit.root.z - 0.02)
			await _grab("/tmp/gun_%s_ads.png" % id)
		gun_root.queue_free()
	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
