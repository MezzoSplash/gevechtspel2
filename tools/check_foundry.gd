extends Node3D
## Headless checks for Foundry: the hall roof is one surface the navmesh can cross (via the skylight
## bridge), the new skylight wallrun walls do not block it, the mezzanine and the yard are reachable,
## and the spawn-to-spawn ground route still exists.
##   godot --headless res://tools/check_foundry.tscn

const TARGETS := {
	"blue_spawn": Vector3(-6, 1.2, 32.0), "orange_spawn": Vector3(-6, 1.2, -32.0),
	"hall_floor": Vector3(0, 0, 5.5), "mezz": Vector3(-9, 3, 0),
	"hill_top": Vector3(-19, 2.6, 0), "courtyard": Vector3(21, 0, 5),
	"roof_w": Vector3(-8.0, 7.3, -3.0), "roof_e": Vector3(7.5, 7.3, 3.0),
	"roof_w_far": Vector3(-8.0, 7.3, 7.5), "roof_e_far": Vector3(7.5, 7.3, -7.5),
	"roof_bridge": Vector3(0, 7.3, 0),
}

var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var map := (load("res://scenes/maps/foundry.tscn") as PackedScene).instantiate() as Node3D
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
	var nav_map := get_world_3d().navigation_map
	var synced := await _wait_for_nav(nav_map, region, nav, TARGETS.blue_spawn)
	if not synced:
		print("  FAIL the baked navmesh never reached the navigation map (%d polygons, iteration %d)" % [nav.get_polygon_count(), NavigationServer3D.map_get_iteration_id(nav_map)])
		fails += 1

	var from: Vector3 = TARGETS.blue_spawn
	for k in TARGETS:
		var to: Vector3 = TARGETS[k]
		var snap := NavigationServer3D.map_get_closest_point(nav_map, to)
		var path := NavigationServer3D.map_get_path(nav_map, from, to, true)
		var ok := path.size() > 0 and path[path.size() - 1].distance_to(snap) < 0.6 and snap.distance_to(to) < 1.2
		_ok(ok, "%-13s snap %s path %d pts" % [k, snap, path.size()])

	# West roof to east roof has to cross the skylight bridge: the wallrun walls must leave that open.
	var cross := NavigationServer3D.map_get_path(nav_map, TARGETS.roof_w_far, TARGETS.roof_e_far, true)
	var over_bridge := false
	for p in cross:
		if absf(p.x) < 4.4 and absf(p.z) < 1.8 and p.y > 7.0:
			over_bridge = true
			break
	_ok(cross.size() > 0 and over_bridge, "the west roof reaches the east roof over the skylight bridge (%d pts)" % cross.size())

	# The floor route must stay on the floor: the roof is an extra level, not the way through.
	var ground := NavigationServer3D.map_get_path(nav_map, TARGETS.blue_spawn, TARGETS.orange_spawn, true)
	var climbed := false
	for p in ground:
		if p.y > 1.5:
			climbed = true
			break
	_ok(ground.size() > 0 and not climbed, "the spawn-to-spawn route stays on the floor (%d pts)" % ground.size())

	print("FOUNDRY CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
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
