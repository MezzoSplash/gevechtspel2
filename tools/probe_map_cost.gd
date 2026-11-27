extends Node
## Meet de kosten van een map vanaf één vaste camera: draw calls, primitives en de frame-tijd.
##   xvfb-run -a godot --path . res://tools/probe_map_cost.tscn -- --map townhouses
## De camera staat op de kade met zicht op de ophaalbrug, hetzelfde punt als de "quay"-foto.
var out := "/tmp"


func _ready() -> void:
	var map_id := &"townhouses"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--map" and i + 1 < args.size():
			map_id = StringName(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene := (load("res://scenes/maps/%s.tscn" % map_id) as PackedScene).instantiate() as Node3D
	add_child(scene)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(8.0, 7.0, 46.0)
	cam.look_at(Vector3(6.0, 0.5, 10.0), Vector3.UP)
	# Een paar frames laten renderen, dan pas meten: de eerste frames bouwen nog shaders en meshes.
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var t0 := Time.get_ticks_usec()
	for i in 30:
		await get_tree().process_frame
	var ms := float(Time.get_ticks_usec() - t0) / 30000.0
	print("MAP COST %s: draw_calls=%d primitives=%d objects=%d frame_ms=%.2f" % [map_id, draws, prims, objs, ms])
	print("MAP COST DONE")
	get_tree().quit()
