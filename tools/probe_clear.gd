extends Node3D
## Prints a coarse free-space map of a scene: for every grid cell, is the volume 0..3.4 m empty?
## Used to place walls, alleys and catch ledges on floor that is actually clear (a wallrun pair that
## intersects a surf or a container is worse than no wallrun pair).
##   godot --headless --path . tools/probe_clear.tscn -- --scene res://scenes/maps/foundry.tscn --step 2

var step := 2.0
var y_clear := 3.4
var y_base := 0.4


func _ready() -> void:
	var scene := "res://scenes/maps/foundry.tscn"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			scene = args[i + 1]
		elif args[i] == "--step" and i + 1 < args.size():
			step = float(args[i + 1])
		elif args[i] == "--y0" and i + 1 < args.size():
			y_base = float(args[i + 1])
		elif args[i] == "--y1" and i + 1 < args.size():
			y_clear = float(args[i + 1])
	var map := (load(scene) as PackedScene).instantiate() as Node3D
	add_child(map)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var space := get_world_3d().direct_space_state
	var region := map.get_node_or_null("Arena") as Node3D
	if region == null:
		print("PROBE: no Arena node")
		get_tree().quit(1)
		return
	var aabb := _bounds(region)
	print("PROBE %s bounds x %.1f..%.1f z %.1f..%.1f step %.1f band %.1f..%.1f" % [scene.get_file(), aabb.position.x, aabb.end.x, aabb.position.z, aabb.end.z, step, y_base, y_clear])
	var z := aabb.position.z
	while z <= aabb.end.z:
		var line := ""
		var x := aabb.position.x
		while x <= aabb.end.x:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, y_clear, z), Vector3(x, y_base - 0.5, z))
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				line += " " # no floor at all
			else:
				var y: float = (hit.position as Vector3).y
				if y > y_base + 0.15:
					line += "#" # something standing in the 0..3.4 band (or a raised floor)
				else:
					line += "."
			x += step
		print("%6.1f %s" % [z, line])
		z += step
	get_tree().quit()


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.get_children():
		if c is CSGShape3D:
			var b: AABB = (c as CSGShape3D).get_aabb()
			# CSG AABB is local to the node: move it to world.
			var xf: Transform3D = (c as CSGShape3D).global_transform
			var t: AABB = xf * b
			box = t if first else box.merge(t)
			first = false
		elif c is Node3D:
			var sub := _bounds(c)
			if sub.size != Vector3.ZERO:
				box = sub if first else box.merge(sub)
				first = false
	return box
