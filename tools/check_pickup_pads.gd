extends Node3D
## #144: every map's pickup pads have to stand somewhere a player can actually walk to and stand on.
## Loads each map scene in turn and checks floor, clearance, distance from the spawns and the flag
## bases. A pad in a wall or on a spot with no floor under it fails here instead of in a playtest.
##   godot --headless res://tools/check_pickup_pads.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var space := get_world_3d().direct_space_state
	for map_id in Maps.ORDER:
		var defs: Array = Maps.pickups(map_id)
		if defs.is_empty():
			print("  FAIL %s has no pickup pads" % map_id)
			fails += 1
			continue
		var scene := load(str(Maps.info(map_id).scene)) as PackedScene
		var map := scene.instantiate() as Node3D
		add_child(map)
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().process_frame
		var spawns: Array = Maps.team_spawns(map_id, 0) + Maps.team_spawns(map_id, 1)
		var bases: Array = Maps.flag_bases(map_id)
		for d in defs:
			var at: Vector3 = d["pos"]
			var t := str(d["type"])
			var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at - Vector3.UP * 0.6)
			var hit := space.intersect_ray(down)
			var on_floor := not hit.is_empty() and absf((hit.position as Vector3).y - at.y) < 0.35
			var body := PhysicsShapeQueryParameters3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 0.5
			body.shape = sphere
			body.transform = Transform3D(Basis(), at + Vector3.UP * 1.0)
			var clear := space.intersect_shape(body, 1).is_empty()
			var near := 999.0
			for sp in spawns:
				near = minf(near, at.distance_to(sp))
			for fb in bases:
				near = minf(near, at.distance_to(fb))
			_ok(on_floor and clear and near > 7.0,
				"%s %s at %s: floor %s, clear %s, %.0f m from the nearest spawn/base" % [
					map_id, t, at, "yes" if on_floor else "NO", "yes" if clear else "NO", near])
		# Reachable, not just standing: bake the navmesh and walk from the first blue spawn to each pad.
		var reach := await _bake_and_probe(map, spawns[0] as Vector3, defs)
		for i in defs.size():
			_ok(bool(reach[i]), "%s %s is reachable on foot from a spawn" % [map_id, defs[i]["type"]])
		remove_child(map)
		map.free()
		await get_tree().process_frame

	print("PICKUP PADS CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


## Bakes this map's navmesh and returns, per pad, whether a path from `from` ends on the pad.
func _bake_and_probe(map: Node3D, from: Vector3, defs: Array) -> Array:
	var out: Array = []
	out.resize(defs.size())
	out.fill(false)
	var region := map.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region == null:
		return out
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_radius = 0.5
	nav.agent_height = 1.75
	nav.agent_max_climb = 0.5
	nav.agent_max_slope = 46.0
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, src, map.get_node("Arena"))
	NavigationServer3D.bake_from_source_geometry_data(nav, src)
	region.navigation_mesh = nav
	var nav_map := get_world_3d().navigation_map
	var start := Time.get_ticks_msec()
	var beat := 0
	while Time.get_ticks_msec() - start < 25000:
		await get_tree().physics_frame
		beat += 1
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0 \
				and NavigationServer3D.map_get_closest_point(nav_map, from) != Vector3.ZERO:
			break
		if beat % 60 == 0:
			region.navigation_mesh = nav
			NavigationServer3D.map_force_update(nav_map)
	for i in defs.size():
		var to: Vector3 = defs[i]["pos"]
		var snap := NavigationServer3D.map_get_closest_point(nav_map, to)
		var path := NavigationServer3D.map_get_path(nav_map, from, to, true)
		out[i] = path.size() > 0 and path[path.size() - 1].distance_to(snap) < 0.6 and snap.distance_to(to) < 1.6
	return out
