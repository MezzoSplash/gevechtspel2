extends Node3D
## #384 screenshots for the PR, to /home/gianni/OpenBot/Shared/gevechtspel2-los2/ (needs a display,
## e.g. xvfb-run): the outline of enemies through a wall, the bash marker in range, and the coconut
## around the body as another player sees it.
const OUT := "/home/gianni/OpenBot/Shared/gevechtspel2-los2"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_env()
	_floor(0.0)
	# A wall the marks have to read through: the bots behind it are still outlined for the driver.
	var wall := StaticBody3D.new()
	var wc := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(14.0, 6.0, 0.5)
	wc.shape = wb
	wall.add_child(wc)
	var wm := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = wb.size
	wm.mesh = wmesh
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.42, 0.45, 0.5)
	wm.material_override = wmat
	wall.add_child(wm)
	wall.position = Vector3(0.0, 3.0, -9.0)
	add_child(wall)

	Game.mode = Game.MODE_FFA
	var me := _pawn(1, false)
	me.global_position = Vector3(0.0, 0.05, 0.0)
	me.rotation.y = 0.0
	var bots: Array[Player] = []
	var spots := [Vector3(-1.2, 0.05, -3.2), Vector3(2.6, 0.05, -12.5), Vector3(0.4, 0.05, -18.0)]
	for i in spots.size():
		var b := _pawn(-3 - i, true)
		b.global_position = spots[i]
		b._bot_brain = null
		bots.append(b)
	for _i in 3:
		await get_tree().physics_frame
	me._spawn_protect = 0.0
	for b in bots:
		b._spawn_protect = 0.0

	# Real entry point: a LOS charge, like 7 kills would give.
	Game.streak_charges[1] = int(Game.streak_charges.get(1, 0)) | Game.CHARGE_LOS
	Game.try_activate_streak(1, 2)
	var hands := LosHands.for_owner(1)
	if hands == null:
		print("LOS did not launch")
		get_tree().quit(1)
		return
	hands.kills = 1 # a chain kill already happened: the HUD and the marks are mid-streak
	hands.global_position = Vector3(0.0, 1.35, 0.0)
	hands._yaw = 0.0
	hands._pitch = 0.0
	hands._pose_cam()
	# Look at the bot in bash range: the gold ring, the others stay cyan.
	var at := bots[0].global_position + Vector3.UP * 1.0
	hands._yaw = atan2(-(at.x - hands.global_position.x), -(at.z - hands.global_position.z))
	hands._pitch = -0.05
	hands._pose_cam()
	await _frames(6)
	await _grab("%s/driver_view.png" % OUT)

	# The coconut as the other team sees it: a third-person camera on the body, no HUD marks.
	hands.queue_free()
	Game.los_view = false
	LosHands._live.clear()
	Game.streak_charges[1] = int(Game.streak_charges.get(1, 0)) | Game.CHARGE_LOS
	Game.try_activate_streak(1, 2)
	var hands2 := LosHands.for_owner(1)
	if hands2 != null:
		hands2.global_position = Vector3(0.0, 1.35, -2.0)
		for c in hands2.get_children():
			if c is LosOutline:
				c.queue_free()
	# Any mark left from the first launch goes too: this frame is about the shell alone.
	for n in get_tree().root.find_children("*", "", true, false):
		if n is LosOutline:
			n.queue_free()
	for b in bots:
		b.visible = false # out of the frame, tags and all
	# The coconut is worn by a body the *other* team sees: show the local pawn's mesh for this shot.
	me.body_mesh.visible = true
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.global_position = Vector3(2.6, 1.6, 2.9)
	cam.look_at(Vector3(0.0, 1.0, 0.0))
	cam.current = true
	await _frames(8)
	await _grab("%s/coconut.png" % OUT)
	get_tree().quit()


func _pawn(id: int, bot: bool) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = id
	p.is_bot = bot
	p.name = ("bot%d" % -id) if bot else str(id)
	add_child(p)
	return p


func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.09, 0.12, 0.18)
	mat.sky_horizon_color = Color(0.22, 0.27, 0.33)
	mat.ground_horizon_color = Color(0.12, 0.14, 0.17)
	mat.ground_bottom_color = Color(0.05, 0.06, 0.08)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)


func _floor(y: float) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	col.shape = box
	body.add_child(col)
	body.position = Vector3(0.0, y - 0.5, 0.0)
	add_child(body)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
