extends Node3D
## Renders the crystal frag (#342) so a human can judge it, in a neutral studio lit like Townhouses
## (same ambient and sun) with a 1.8 m pawn-sized post for scale: close-ups at rest (ice band, the cap in
## a team colour) and in the last tenth of the fuse (red band), a few tumbling frames of a throw with its
## streak, and the boom at three moments (shards and ground ring). Not in run_checks.sh (needs a screen).
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     res://tools/shot_grenade.tscn -- --out /tmp
var out := "/tmp"
var cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	Game.mode = Game.MODE_TDM
	_studio()
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	await _settle(0.1)

	# At rest, close: the team colour on the cap, the ice band, then the last tenth of the fuse.
	var g := Grenade.spawn_visual(self, Vector3(2.5, 0.3, 1.5), Vector3.ZERO)
	g.thrower_team = 1
	g.look.set_team(1)
	await _settle(0.4)
	cam.fov = 35.0
	var at := g.global_position
	g._age = 0.0
	await _shot("rest", at + Vector3(0.55, 0.3, 0.45), at)
	g._age = Grenade.FUSE - 0.06
	await _settle(0.02)
	await _shot("danger", at + Vector3(0.55, 0.3, 0.45), at)
	g.queue_free()

	# Scale: the frag at the post's foot.
	var s := Grenade.spawn_visual(self, Vector3(0.7, 0.2, 0.3), Vector3.ZERO)
	s.look.set_team(0)
	await _settle(0.3)
	s._age = 0.0
	cam.fov = 50.0
	await _shot("scale", Vector3(3.2, 1.6, 3.4), Vector3(0.4, 0.6, 0.0))
	s.queue_free()

	# A throw, seen from the side: three frames of the tumble and the streak.
	var f := Grenade.spawn_visual(self, Vector3(-6.0, 1.5, -2.0), Grenade.initial_velocity(Vector3(1.0, 0.1, 0.0)))
	f.look.set_team(0)
	cam.fov = 50.0
	for i in 3:
		await _settle(0.09)

		await _shot("flight%d" % i, f.global_position + Vector3(0.0, 0.4, 3.2), f.global_position)
	f.queue_free()

	# The boom on the floor at three moments, from where a player would stand.
	cam.fov = 70.0
	var boom_at := Vector3(0.0, 0.08, 0.0)
	var eye := Vector3(0.0, 1.6, 9.0)
	Grenade.play_boom(boom_at)
	var t := 0.0
	for mark in [0.04, 0.12, 0.24]:
		await _settle(float(mark) - t)
		t = float(mark)
		await _shot("boom%d" % int(round(t * 100.0)), eye, boom_at + Vector3.UP * 0.8)
	print("SHOT grenade: done -> %s/grenade-*.png" % out)
	get_tree().quit(0)


## Floor, the Townhouses sky/ambient and sun, and a 1.8 m post (pawn height, capsule radius 0.4).
func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.56, 0.62)
	env.ambient_light_energy = 0.58
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis(Vector3(0.766, 0, -0.6428), Vector3(-0.4545, 0.7071, -0.5417), Vector3(0.4545, 0.7071, 0.5417)), Vector3(6, 18, 8))
	sun.light_energy = 1.12
	sun.light_color = Color(1, 0.95, 0.88)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(40, 1, 40)
	floor_mesh.mesh = fm
	floor_mesh.position.y = -0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.27) # Townhouses asphalt
	mat.roughness = 0.9
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	add_child(floor_body)
	var post := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	post.mesh = cap
	post.position = Vector3(-0.2, 0.9, -0.4)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.45, 0.47, 0.5)
	post.material_override = pm
	add_child(post)


func _settle(t: float) -> void:
	var left := t
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _shot(tag: String, eye: Vector3, at: Vector3) -> void:
	cam.global_position = eye
	cam.look_at(at, Vector3.UP)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/grenade-%s.png" % [out, tag])
