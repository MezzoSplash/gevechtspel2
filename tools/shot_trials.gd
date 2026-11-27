extends Node
## Beeldbewijs voor Trials (#325): de baan met markers, de ghost en de HUD, vanuit de pawn.
##   xvfb-run -a godot --path . res://tools/shot_trials.tscn -- --out DIR
var out := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	await _shots()
	print("SHOT TRIALS: done")
	get_tree().quit()


func _shots() -> void:
	var scene := (load("res://scenes/maps/townhouses.tscn") as PackedScene).instantiate() as Node3D
	add_child(scene)
	await get_tree().physics_frame
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = 1
	p.set_physics_process(false)
	add_child(p)
	await get_tree().physics_frame
	var run := Node3D.new()
	run.set_script(load("res://scripts/trials_run.gd"))
	add_child(run)
	run.setup(scene, p, &"townhouses", 0)
	# Een ghost van een verzonnen run, zodat het beeld laat zien hoe die eruitziet: alleen een lichaam.
	var fake := PackedFloat32Array()
	var cps: Array = run.checkpoints
	for i in cps.size() - 1:
		for s in 20:
			var t := float(s) / 20.0
			var at: Vector3 = (cps[i] as Vector3).lerp(cps[i + 1], t)
			fake.append(at.x)
			fake.append(at.y)
			fake.append(at.z)
			fake.append(0.0)
	run._ghost_data = fake
	run._build_ghost()

	var layer := CanvasLayer.new()
	layer.set_script(load("res://scripts/hud/trials_hud.gd"))
	add_child(layer)
	layer.bind(run)

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var views := {
		"start": [Vector3(8.0, 7.0, 46.0), Vector3(6.0, 0.5, 10.0)],
		"brug": [Vector3(7.0, 6.0, 20.0), Vector3(0.0, 0.5, -2.0)],
	}
	for key in views:
		var v: Array = views[key]
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		run.run_ms = 7450
		run.running = true
		if key == "brug":
			run.next_cp = 3
		layer.refresh(run)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/trials_%s.png" % [out, key]
		img.save_png(path)
		print("saved ", path)
