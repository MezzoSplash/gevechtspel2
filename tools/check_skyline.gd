extends Node3D
## Headless checks for Skyline: navmesh connects every roof, spawns stand on a roof.
##   godot --headless res://tools/check_skyline.tscn

const TARGETS := {
	"blue_spawn": Vector3(0, 12, 41), "orange_spawn": Vector3(0, 12, -41),
	"tower_roof_B": Vector3(4, 12, 29.5), "tower_room_B": Vector3(2, 6, 23), "tower_room_O": Vector3(-2, 6, -23),
	"mid": Vector3(5, 6, -6), "WA_B": Vector3(-24.5, 9, 39), "WB_B": Vector3(-22, 6, 12), "WM": Vector3(-25, 4, -1),
	"EM": Vector3(25, 4, 1), "EA_B": Vector3(22, 15, 33), "EB_B": Vector3(26, 9, 9.2),
	"EA_O": Vector3(-22, 15, -33), "surf_deck_B": Vector3(-14, 6, 6), "surf_deck_O": Vector3(14, 6, -6), "WA_O": Vector3(24.5, 9, -39),
}

func _ready() -> void:
	var map := (load("res://scenes/maps/skyline.tscn") as PackedScene).instantiate() as Node3D
	add_child(map)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var region := map.get_node("NavigationRegion3D") as NavigationRegion3D
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
	print("navmesh polygons: %d, kill_y %s" % [nav.get_polygon_count(), map.get_meta(&"kill_y", "none")])
	var nav_map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(nav_map, nav.cell_size)
	NavigationServer3D.map_set_cell_height(nav_map, nav.cell_height)
	NavigationServer3D.map_set_active(nav_map, true)
	var reg := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(reg, nav_map)
	NavigationServer3D.region_set_navigation_mesh(reg, nav)
	for i in 10:
		await get_tree().physics_frame
	var fails := 0
	var from: Vector3 = TARGETS.blue_spawn
	for k in TARGETS:
		var to: Vector3 = TARGETS[k]
		var snap := NavigationServer3D.map_get_closest_point(nav_map, to)
		var path := NavigationServer3D.map_get_path(nav_map, from, to, true)
		var ok := path.size() > 0 and path[path.size() - 1].distance_to(snap) < 0.6 and snap.distance_to(to) < 1.0
		print("  %s %-14s snap %s path %d pts" % ["ok  " if ok else "FAIL", k, snap, path.size()])
		if not ok:
			fails += 1
	var space := get_world_3d().direct_space_state
	for team in 2:
		for p in Maps.team_spawns(&"skyline", team):
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -1.0, 0))
			var hit := space.intersect_ray(q)
			if hit.is_empty() or absf(hit.position.y - p.y) > 0.05:
				print("  FAIL spawn %s has no roof under it" % p)
				fails += 1
	for p in Maps.ffa_spawns(&"skyline"):
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -1.0, 0))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf(hit.position.y - p.y) > 0.05:
			print("  FAIL ffa spawn %s (hit %s)" % [p, hit.get("position", "none")])
			fails += 1
	# Navmesh must not lie on the surf faces (over the walk limit). Sample along both ridges.
	for zz in [14.0, 20.0, 26.0, 32.0]:
		for sx in [-1.0, 1.0]:
			var on := Vector3(-13.0 + sx * 1.6, 11.0, zz) * Vector3(1, 1, 1)
			for sgn in [1.0, -1.0]:
				var q := Vector3(on.x * sgn, on.y, on.z * sgn)
				# An island on a kicker bevel is harmless; only a path from the spawn counts.
				var pth := NavigationServer3D.map_get_path(nav_map, from, q, true)
				var c: Vector3 = pth[pth.size() - 1] if pth.size() > 0 else Vector3.INF
				if c.distance_to(q) < 1.2:
					print("  FAIL navmesh on surf face near %s (%s)" % [q, c])
					fails += 1
	# Sightline: eye height from the Orange half's surf exit and the Blue deck to Blue spawn points.
	var open := 0
	for eye in [Vector3(-13, 7.7, 9.5), Vector3(-14, 7.7, 6), Vector3(-22, 7.7, 14)]:
		for p in Maps.team_spawns(&"skyline", 0):
			var q := PhysicsRayQueryParameters3D.create(eye, p + Vector3(0, 1.6, 0))
			if space.intersect_ray(q).is_empty():
				open += 1
	print("  clear lines from the surf exit / WB into Blue spawn points: %d of 36" % open)
	print("SKYLINE CHECK: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(fails)
