extends Node3D
## Headless checks for Rooftops (v2, tools/gen_rooftops.py): the navmesh reaches the roofs, the launch
## decks, the bridges, the flanks and the court, the ground route between the spawns exists, and the
## flow lines ride: a bare capsule on the flank surf and in the court gutter has to get where the map
## says it goes, fast enough to cash a strip.
##   godot --headless res://tools/check_rooftops.tscn

const TARGETS := {
	"blue_spawn": Vector3(-9, 0, 41), "orange_spawn": Vector3(9, 0, -41),
	"court_s": Vector3(12, 0, 10), "court_n": Vector3(-12, 0, -10),
	"flank_w": Vector3(-28, 0, 0), "flank_e": Vector3(28, 0, 0),
	"launch_b": Vector3(-24, 6, 29.7), "launch_o": Vector3(24, 6, -29.7),
	"roof_blue": Vector3(-13, 6, 20), "roof_orange": Vector3(13, 6, -20),
	"bridge_ws": Vector3(-14, 6, 8), "bridge_wn": Vector3(-14, 6, -8),
	"bridge_es": Vector3(14, 6, 8), "bridge_en": Vector3(14, 6, -8),
	"ramp_top_b": Vector3(4.4, 6, 17.5), "ramp_top_o": Vector3(-4.4, 6, -17.5),
}
## Flow lines: [start on the face, velocity, push into the face, max end z (signed for Blue), min ride s].
## Orange's are the half-turn. The bare capsule surfs worse than a player, so the bars are low.
const RIDES := {
	"flank": [Vector3(-32.6, 7.4, 26.0), Vector3(0, 0, -11.4), Vector3(-1, 0, 0), -14.0, 2.0],
	"court": [Vector3(-4.7, 5.5, 15.0), Vector3(0, 0, -11.4), Vector3(-1, 0, 0), -1.0, 0.8],
}
const STRIP_SPEED := 13.5 # Player.STRIP_SPEED: a ride that never gets there cannot cash a strip
const EYE := 1.6
const MAX_LANE := 35.0
const HX := 35.0 # inner half-width, gen_rooftops.py
const HZ := 50.0
const SINK_HOLD := 3.0 # m/s down: the test surfer strafes into the face while it sinks faster

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

	# Every spawn gets out: a corner sealed by cover once trapped three spawns per team, and the
	# pickup check only walks from the first one.
	var stuck: Array = []
	var all_spawns: Array = Maps.team_spawns(&"rooftops", 0) + Maps.team_spawns(&"rooftops", 1) + Maps.info(&"rooftops").ffa_spawns
	for sp in all_spawns:
		var out := _path(nav_map, sp, TARGETS.court_s)
		var goal := NavigationServer3D.map_get_closest_point(nav_map, TARGETS.court_s)
		if out.is_empty() or out[out.size() - 1].distance_to(goal) > 0.6:
			stuck.append(sp)
	_ok(stuck.is_empty(), "every team and FFA spawn has a walk to the court (%d spawns, stuck: %s)" % [all_spawns.size(), stuck])
	# Each skybridge is one roof-level route: end to end it never leaves 6 m.
	for side in ["w", "e"]:
		var bridge := _path(nav_map, TARGETS["bridge_%ss" % side], TARGETS["bridge_%sn" % side])
		var level := bridge.size() > 0
		for p in bridge:
			if absf(p.y - 6.0) > 0.8:
				level = false
				break
		_ok(level, "the %s skybridge is a roof-level route end to end (%d pts)" % [side, bridge.size()])
	for k in RIDES:
		await _ride(k, RIDES[k], 1.0)
		await _ride(k, RIDES[k], -1.0)
	_lanes()
	_spawn_sight()

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


## docs/art: "De langste schone lane blijft onder de 35 m". Eye-height rays along Z and along X over
## the whole ground floor, every metre; a clean lane is a ray that hits nothing for that long while the
## floor under both ends is the ground. The longest one is printed with where it is, so a failure says
## which lane to break.
func _lanes() -> void:
	var space := get_world_3d().direct_space_state
	var worst := 0.0
	var where := ""
	for axis in [Vector3.FORWARD, Vector3.RIGHT]:
		var across := Vector3.RIGHT if axis == Vector3.FORWARD else Vector3.FORWARD
		for i in range(-49, 50):
			var c: Vector3 = across * float(i)
			if absf(c.x) > HX - 1.0:
				continue
			# Walk the line: from each ground point, how far the eye sees along it.
			for j in range(-49, 50, 2):
				var from: Vector3 = c + axis * float(j) + Vector3.UP * EYE
				if absf(from.x) > HX - 1.0 or absf(from.z) > HZ - 1.0 or not _ground_at(space, from):
					continue
				var q := PhysicsRayQueryParameters3D.create(from, from - axis * 120.0)
				q.collision_mask = 1
				var hit := space.intersect_ray(q)
				var d: float = from.distance_to(hit.position) if not hit.is_empty() else 120.0
				if d > worst:
					worst = d
					where = "%s looking %s" % [from.snapped(Vector3.ONE * 0.1), -axis]
	_ok(worst <= MAX_LANE, "longest clean ground lane at eye height: %.1f m (max %.0f), from %s" % [worst, MAX_LANE, where])


## Standing room on the ground: floor under the eye and nothing for 3 m over it. The second test
## drops points inside a solid (a ray started in a surf wedge sees through it) and the rooms (CQB,
## not a lane).
func _ground_at(space: PhysicsDirectSpaceState3D, eye: Vector3) -> bool:
	var up := PhysicsRayQueryParameters3D.create(eye + Vector3.UP * 3.0, eye)
	up.collision_mask = 1
	if not space.intersect_ray(up).is_empty():
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.DOWN * 3.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit.position as Vector3).y < 0.2 and (hit.normal as Vector3).y > 0.9


## No spawn sees the other team's spawn: every pair at eye height is blocked.
func _spawn_sight() -> void:
	var spawns: Array = [Maps.team_spawns(&"rooftops", 0), Maps.team_spawns(&"rooftops", 1)]
	var space := get_world_3d().direct_space_state
	var open := 0
	var first := ""
	for a in spawns[0]:
		for b in spawns[1]:
			var q := PhysicsRayQueryParameters3D.create((a as Vector3) + Vector3.UP * EYE, (b as Vector3) + Vector3.UP * EYE)
			q.collision_mask = 1
			if space.intersect_ray(q).is_empty():
				open += 1
				if first == "":
					first = "%s -> %s" % [a, b]
	_ok(open == 0, "no blue spawn sees an orange spawn (%d of %d pairs open%s)" % [
		open, spawns[0].size() * spawns[1].size(), (", first " + first) if first != "" else ""])


## Rides a flow line with a real pawn and real keys: the pawn faces down the line and strafes toward
## the face (`push` says which side) while it sinks faster than SINK_HOLD, the way a player feathers
## the key to stay on the line instead of climbing to the ridge. A bare capsule cannot surf a 57°
## face (it slides off the toe in a second), so the check drives Player's own movement instead.
## `sign` -1 rides Orange's half-turn copy.
func _ride(label: String, r: Array, sign: float) -> void:
	var start: Vector3 = r[0]
	var vel: Vector3 = r[1]
	var push: Vector3 = r[2]
	Game.is_offline = true
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = 1
	p.set_physics_process(false)
	add_child(p)
	p._spawn_protect = 999.0
	await get_tree().physics_frame
	p.global_position = Vector3(start.x * sign, start.y, start.z * sign)
	var v := Vector3(vel.x * sign, vel.y, vel.z * sign)
	p.velocity = v
	p.rotation.y = atan2(-v.x, -v.z) # face the travel
	var key := ""
	var pushed := Vector3(push.x * sign, 0.0, push.z * sign)
	if pushed.length_squared() > 0.0:
		key = "move_right" if p.global_transform.basis.x.dot(pushed) > 0.0 else "move_left"
	p.set_physics_process(true)
	var dt := 1.0 / 60.0
	var ride := 0.0
	var top := 0.0
	var landed := 0
	for f in 360:
		if key != "":
			if p.velocity.y < -SINK_HOLD:
				Input.action_press(key)
			elif p.velocity.y > -SINK_HOLD * 0.3:
				Input.action_release(key)
		await get_tree().physics_frame
		if p.is_surfing():
			ride += dt
		top = maxf(top, Vector2(p.velocity.x, p.velocity.z).length())
		if OS.has_environment("RIDE_TRACE") and f % 6 == 0:
			print("    %s t=%.2f pos=%s vel=%s surf=%s floor=%s" % [label, f * dt, p.global_position.snapped(Vector3.ONE * 0.1), p.velocity.snapped(Vector3.ONE * 0.1), p.is_surfing(), p.is_on_floor()])
		landed = landed + 1 if p.is_on_floor() else 0
		if landed > 20 and f > 30:
			break
	if key != "":
		Input.action_release(key)
	var end := p.global_position
	p.queue_free()
	var team := "blue" if sign > 0.0 else "orange"
	var far := end.z * sign <= float(r[3])
	_ok(far and ride >= float(r[4]) and top >= STRIP_SPEED,
		"%s %s ride: %.2f s surfing, top %.1f m/s, ends at %s (blue wants z <= %.1f)" % [
			team, label, ride, top, end.snapped(Vector3.ONE * 0.1), float(r[3])])


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
