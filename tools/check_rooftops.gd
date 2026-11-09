extends Node3D
## Headless checks for Rooftops: the navmesh reaches both roofs, the court alley and both
## skybridges, and the ground route between the spawns still exists.
##   godot --headless res://tools/check_rooftops.tscn

const TARGETS := {
	"blue_spawn": Vector3(-6, 0, 32.6), "orange_spawn": Vector3(-6, 0, -32.6),
	"court_s": Vector3(0, 0, 11), "court_n": Vector3(0, 0, -11),
	"deck_w": Vector3(-24, 4, 24), "deck_e": Vector3(24, 4, -24),
	"roof_blue": Vector3(-13, 6, 20), "roof_orange": Vector3(-13, 6, -20),
	"bridge_ws": Vector3(-13, 6, 10), "bridge_wn": Vector3(-13, 6, -10),
	"bridge_es": Vector3(13, 6, 10), "bridge_en": Vector3(13, 6, -10),
	"roof_mid": Vector3(0, 6, 20),
}

var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", msg])
	if not c:
		fails += 1


func _path(nav_map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(nav_map, from, to, true)


func _ready() -> void:
	var map := (load("res://scenes/maps/rooftops.tscn") as PackedScene).instantiate() as Node3D
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
	print("navmesh polygons: %d" % nav.get_polygon_count())
	# The scene's region is already on the world's map: wait for the bake to reach it (a private map
	# races the synchronization and errors out under load), then query.
	var nav_map := get_world_3d().navigation_map
	var synced := await _wait_for_nav(nav_map, region, nav, TARGETS.blue_spawn)
	if not synced:
		print("  FAIL the baked navmesh never reached the navigation map (%d polygons, iteration %d)" % [nav.get_polygon_count(), NavigationServer3D.map_get_iteration_id(nav_map)])
		fails += 1

	var from: Vector3 = TARGETS.blue_spawn
	for k in TARGETS:
		var to: Vector3 = TARGETS[k]
		var snap := NavigationServer3D.map_get_closest_point(nav_map, to)
		var path := _path(nav_map, from, to)
		var ok := path.size() > 0 and path[path.size() - 1].distance_to(snap) < 0.6 and snap.distance_to(to) < 1.0
		_ok(ok, "%-13s snap %s path %d pts" % [k, snap, path.size()])

	# The roof route has to cross the skybridge, not detour over the courtyard floor and back up.
	var roof_path := _path(nav_map, TARGETS.roof_blue, TARGETS.roof_orange)
	var crossed := false
	for p in roof_path:
		if absf(p.y - 6.0) < 0.8 and absf(p.z) < 6.0 and absf(p.x) > 10.0:
			crossed = true
			break
	_ok(crossed, "the blue-roof to orange-roof route runs across a skybridge at 6 m (%d pts)" % roof_path.size())

	# The ground route spawn to spawn must not need the bridges (both routes must exist: the bridge
	# is a shortcut for players, not the only way for the navmesh).
	var ground := _path(nav_map, TARGETS.blue_spawn, TARGETS.orange_spawn)
	var on_roof := false
	for p in ground:
		if p.y > 1.5:
			on_roof = true
			break
	_ok(ground.size() > 0 and not on_roof, "the spawn-to-spawn ground route stays on the floor (%d pts)" % ground.size())

	print("ROOFTOPS CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


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
