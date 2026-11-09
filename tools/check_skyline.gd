extends Node3D
## Headless checks for Skyline: navmesh connects every roof, spawns stand on a roof.
##   godot --headless res://tools/check_skyline.tscn

const TARGETS := {
	"blue_spawn": Vector3(0, 12, 41), "orange_spawn": Vector3(0, 12, -41),
	"tower_roof_B": Vector3(4, 12, 29.5), "tower_room_B": Vector3(2, 6, 23), "tower_room_O": Vector3(-2, 6, -23),
	"mid": Vector3(5, 6, -6), "WA_B": Vector3(-24.5, 9, 39), "WB_B": Vector3(-22, 6, 12), "WM": Vector3(-25, 4, -1),
	"EM": Vector3(25, 4, 1), "EA_B": Vector3(22, 15, 33), "EB_B": Vector3(26, 9, 9.2),
	"EA_O": Vector3(-22, 15, -33), "surf_deck_B": Vector3(-20, 6, 18), "surf_deck_O": Vector3(20, 6, -18), "WA_O": Vector3(24.5, 9, -39),
	"run_alley_B": Vector3(25, 15, 30), "run_alley_O": Vector3(-25, 15, -30),
	"spine_catch": Vector3(0, 9, 33), "surf_pad": Vector3(-17.5, 9.6, 30), "EB_catch": Vector3(27, 9, 16), "WB_catch": Vector3(-33, 6, 23.5),
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
	# Query the world's own navigation map instead of a private one: the scene's region already lives
	# there, so the map is synchronized before the bake lands and a query can never hit the
	# "made before first map synchronization" engine ERROR (the runner counts an ERROR line as a
	# failure even when every assertion passed). What we do wait for is the baked mesh reaching the
	# map, and for that a probe query is the only honest signal - it just no longer errors.
	var nav_map := get_world_3d().navigation_map
	var synced := await _wait_for_nav(nav_map, region, nav, TARGETS.blue_spawn)
	if not synced:
		print("  FAIL the baked navmesh never reached the navigation map (%d polygons, iteration %d)" % [
			nav.get_polygon_count(), NavigationServer3D.map_get_iteration_id(nav_map)])
	var fails := 0 if synced else 1
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
	# #212: no spawn may see the other team's spawn, eye to eye, on any pair. The outer columns
	# (x = +/-13) used to look straight across to their half-turn counterpart, between baffles that
	# stopped at |x| = 10 and a sign that only covers the centre.
	var open_pairs := 0
	var blue := Maps.team_spawns(&"skyline", 0)
	for a in blue:
		for b in Maps.team_spawns(&"skyline", 1):
			var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.6, 0), b + Vector3(0, 1.6, 0))
			if space.intersect_ray(q).is_empty():
				open_pairs += 1
				if open_pairs <= 3:
					print("  open spawn sight line %s -> %s" % [a, b])
	if open_pairs > 0:
		print("  FAIL %d of %d spawn pairs see each other" % [open_pairs, blue.size() * blue.size()])
		fails += 1
	print("SKYLINE CHECK: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(fails)


## Waits for a baked mesh to reach the world's navigation map, and nudges it if it does not.
## A frame count is the wrong unit: this loop runs as fast as the machine allows, so 900 frames is six
## seconds on a loaded box and fifteen on an idle one. Time budget instead, with a periodic
## re-assignment of the mesh plus map_force_update, because a dropped assignment never lands at all.
## The closest-point query is only asked once the map reports a synchronization: asking earlier is the
## ENGINE ERROR that made these checks flaky (#211).
func _wait_for_nav(nav_map: RID, region: NavigationRegion3D, nav: NavigationMesh, probe: Vector3, budget_ms := 25000) -> bool:
	var start := Time.get_ticks_msec()
	var beat := 0
	while Time.get_ticks_msec() - start < budget_ms:
		await get_tree().physics_frame
		beat += 1
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0 \
				and NavigationServer3D.map_get_closest_point(nav_map, probe) != Vector3.ZERO:
			return true
		if beat % 60 == 0:
			region.navigation_mesh = nav
			NavigationServer3D.map_force_update(nav_map)
	return false
