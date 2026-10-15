extends SceneTree
## Headless checks for Quay. Run after `python3 tools/gen_quay.py` (it writes /tmp/quay_probe.json):
##   godot --headless --path . -s res://tools/check_quay.gd
## Prints PROBE/WALK/NAV/SYM/HEAD lines and a final "QUAY CHECK OK" or "QUAY CHECK FAILED".

var MAP := "res://scenes/maps/quay.tscn"
const PROBE_JSON := "/tmp/quay_probe.json"

var fails := 0
var space: PhysicsDirectSpaceState3D
var map: Node3D


func _init() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL ", msg)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			MAP = a.substr(4)
	map = (load(MAP) as PackedScene).instantiate()
	root.add_child(map)
	for i in 8:
		await physics_frame
	space = root.get_world_3d().direct_space_state
	_probes()
	await _walks()
	await _nav()
	_symmetry()
	_headroom()
	print("QUAY CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return space.intersect_ray(q)


func _classify(hit: Dictionary) -> String:
	if hit.is_empty():
		return "clear"
	var n: Vector3 = hit.normal
	var y: float = hit.position.y
	if n.y > 0.97:
		if absf(y) < 0.15:
			return "floor"
		if absf(y - 4.0) < 0.15:
			return "deck"
		if absf(y - 10.0) < 0.15:
			return "roof"
		return "flat@%.2f" % y
	if n.y > 0.62:
		return "slope"
	if n.y >= 0.15:
		return "surf"
	return "wall"


func _probes() -> void:
	var f := FileAccess.open(PROBE_JSON, FileAccess.READ)
	if f == null:
		_fail("no %s (run tools/gen_quay.py first)" % PROBE_JSON)
		return
	var list: Array = JSON.parse_string(f.get_as_text())
	var bad := 0
	for p in list:
		var a := Vector3(p.from[0], p.from[1], p.from[2])
		var b := Vector3(p.to[0], p.to[1], p.to[2])
		var got := _classify(_ray(a, b))
		var want: String = p.want
		var ok := got == want
		if want == "slope" and got in ["slope"]:
			ok = true
		if not ok:
			bad += 1
			_fail("probe %s want %s got %s" % [p.name, want, got])
	print("PROBE %d rays, %d bad" % [list.size(), bad])


## Walks a standing capsule through waypoints with the game's StepUp, like a player holding W.
func _walk(label: String, pts: Array, speed := 6.0) -> void:
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	body.collision_layer = 2
	body.collision_mask = 1
	body.floor_max_angle = deg_to_rad(45.0)
	body.floor_snap_length = 0.2
	root.add_child(body)
	body.global_position = pts[0] + Vector3(0, 0.05, 0)
	var wi := 1
	var stuck := 0
	var last := body.global_position
	var frames := 0
	var dt := 1.0 / 60.0
	while wi < pts.size() and frames < 60 * 60:
		frames += 1
		var target: Vector3 = pts[wi]
		var to := target - body.global_position
		to.y = 0.0
		if to.length() < 0.45:
			wi += 1
			stuck = 0
			continue
		var v := to.normalized() * speed
		var on_floor := body.is_on_floor()
		body.velocity = Vector3(v.x, (0.0 if on_floor else body.velocity.y) - 20.0 * dt, v.z)
		var pre := body.velocity
		body.move_and_slide()
		StepUp.try_step(body, pre, on_floor, dt)
		await physics_frame
		if frames % 30 == 0:
			if body.global_position.distance_to(last) < 0.25:
				stuck += 1
				if stuck >= 4:
					break
			else:
				stuck = 0
			last = body.global_position
	var endp := body.global_position
	body.queue_free()
	if wi < pts.size():
		_fail("walk %s stuck before waypoint %d %s at %s" % [label, wi, pts[wi], endp])
	else:
		print("WALK %s ok, end %s" % [label, endp.snapped(Vector3.ONE * 0.01)])


func _mirror(pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append(Vector3(-p.x, p.y, -p.z))
	return out


func _walks() -> void:
	var routes := {
		# West side lane, blue yard strip to orange yard strip, over the new ramps and under the arch.
		"west_lane": [Vector3(-20, 0, 52), Vector3(-38, 0, 51), Vector3(-38, 0, 41.3), Vector3(-38, 0, 38.5),
			Vector3(-38, 4, 23), Vector3(-38, 4, 8), Vector3(-37, 4, -8), Vector3(-40, 4, -20),
			Vector3(-40, 0, -41), Vector3(-39, 0, -51), Vector3(-20, 0, -52)],
		# Along the foot of the flank surf, on the new deck.
		"surf_foot": [Vector3(-41.2, 4, 20), Vector3(-41.2, 4, 5), Vector3(-41.2, 4, -2), Vector3(-43.5, 4, -6)],
		# Quay ramps (deck <-> dock), unchanged, as a regression walk.
		"quay_ramp": [Vector3(-26, 4, 18.1), Vector3(-12, 0, 18.1), Vector3(-6, 0, 18.1)],
	}
	var extra: Dictionary = map.get_meta("quay_walks", {})
	for k in extra:
		routes[k] = extra[k]
	for k in routes:
		await _walk(k + "_blue", routes[k])
		await _walk(k + "_orange", _mirror(routes[k]))


func _ground(x: float, z: float, top := 30.0) -> Vector3:
	var h := _ray(Vector3(x, top, z), Vector3(x, -2, z))
	return h.position if not h.is_empty() else Vector3(x, 0, z)


func _nav() -> void:
	var region := map.get_node("NavigationRegion3D") as NavigationRegion3D
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 46.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, map.get_node("Arena"))
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	region.navigation_mesh = nm
	var rid := region.get_navigation_map()
	for i in 120:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(rid) > 0 and NavigationServer3D.map_get_closest_point(rid, Vector3(0, 0, 11)) != Vector3.ZERO:
			break
	print("NAV map iteration %d, %d polygons" % [NavigationServer3D.map_get_iteration_id(rid), nm.get_polygon_count()])
	var info: Dictionary = Maps.info(&"quay")
	var blue: Vector3 = info.team_spawns[0][2]
	var orange: Vector3 = info.team_spawns[1][2]
	var targets := {
		"orange_spawn": orange,
		"west_deck": Vector3(-37, 4, 0), "east_deck": Vector3(37, 4, 0),
		"west_pocket": Vector3(-38, 0, 46), "east_lane": Vector3(39, 0, 46),
		"orange_west_lane": Vector3(-39, 0, -46), "orange_pocket": Vector3(38, 0, -46),
		"dock_mid": Vector3(0, 0, 11), "dock_mid_o": Vector3(0, 0, -11),
		"blue_west_roof": Vector3(-24, 10, 38), "orange_east_roof": Vector3(24, 10, -38),
		"blue_east_roof": Vector3(24, 10, 40), "orange_west_roof": Vector3(-24, 10, -40),
	}
	var extra: Dictionary = map.get_meta("quay_nav", {})
	for k in extra:
		targets[k] = extra[k]
	for k in targets:
		for side in [0, 1]:
			var from := blue if side == 0 else orange
			var t: Vector3 = targets[k]
			if side == 1:
				t = Vector3(-t.x, t.y, -t.z)
				if k == "orange_spawn":
					t = blue
			var a := NavigationServer3D.map_get_closest_point(rid, from)
			var b := NavigationServer3D.map_get_closest_point(rid, t)
			var path := NavigationServer3D.map_get_path(rid, a, b, true)
			var L := 0.0
			for i in range(1, path.size()):
				L += path[i].distance_to(path[i - 1])
			var end_ok := path.size() > 0 and path[path.size() - 1].distance_to(b) < 0.8 and b.distance_to(t) < 1.2
			var lbl := "%s from %s" % [k, "blue" if side == 0 else "orange"]
			if not end_ok:
				_fail("nav %s: no path (closest %s, end %s)" % [lbl, b, path[path.size() - 1] if path.size() else "none"])
			else:
				print("NAV %-28s %.0f m" % [lbl, L])


## Half-turn symmetry of the walkable/visible top surface: (x, z) against (-x, -z).
func _symmetry() -> void:
	var bad := 0
	var worst := []
	var x := -44.75
	while x <= 44.75:
		var z := 0.25
		while z <= 60.75:
			var a := _ray(Vector3(x, 30, z), Vector3(x, -2, z))
			var b := _ray(Vector3(-x, 30, -z), Vector3(-x, -2, -z))
			var ya: float = a.position.y if not a.is_empty() else -9.0
			var yb: float = b.position.y if not b.is_empty() else -9.0
			# The cross surf is one piece through the middle (faces orange): skip its strip.
			var cross := absf(z) < 2.6 and absf(x) < 10.5
			if absf(ya - yb) > 0.06 and not cross:
				bad += 1
				if worst.size() < 12:
					worst.append("(%.1f, %.1f) %.2f vs %.2f" % [x, z, ya, yb])
			z += 1.0
		x += 1.0
	if bad > 0:
		_fail("symmetry: %d of the 1 m samples differ, e.g. %s" % [bad, ", ".join(worst)])
	else:
		print("SYM half-turn ok")


## Head traps: a floor you can walk onto with a ceiling under 2.0 m but over 0.3 m above it.
## Lists them so new geometry (stairs, arch, gantry, slabs) can be checked by name.
func _headroom() -> void:
	var traps := []
	var x := -44.75
	while x <= 44.75:
		var z := -60.75
		while z <= 60.75:
			var top := 30.0
			for layer in 4:
				var h := _ray(Vector3(x, top, z), Vector3(x, -2, z))
				if h.is_empty():
					break
				var fy: float = h.position.y
				var n: Vector3 = h.normal
				if n.y > 0.7:
					var up := _ray(Vector3(x, fy + 0.05, z), Vector3(x, fy + 2.0, z))
					if not up.is_empty():
						var gap: float = up.position.y - fy
						if gap > 0.3 and gap < 1.95:
							traps.append(Vector3(x, fy, z))
				top = fy - 0.3
				if top < 0.5:
					break
			z += 0.5
		x += 0.5
	var dump := FileAccess.open("/tmp/quay_head.txt", FileAccess.WRITE)
	for t in traps:
		dump.store_line("%.2f %.2f %.2f" % [t.x, t.y, t.z])
	dump.close()
	# Spots that were already low before the rework (window sills, under the loods stairs).
	# Anything not on that list within 0.3 m is new and fails the check.
	var known := {}
	var kf := FileAccess.open("res://tools/quay_head_known.txt", FileAccess.READ)
	while kf != null and not kf.eof_reached():
		var parts := kf.get_line().split(" ", false)
		if parts.size() == 3:
			var key := "%.2f %.2f" % [float(parts[0]), float(parts[2])]
			if not known.has(key):
				known[key] = []
			known[key].append(float(parts[1]))
	var unknown := []
	for t in traps:
		var key := "%.2f %.2f" % [t.x, t.z]
		var ok := false
		for ky in known.get(key, []):
			if absf(ky - t.y) < 0.3:
				ok = true
		if not ok:
			unknown.append(t)
	print("HEAD %d low-ceiling floor samples, %d outside the known spots" % [traps.size(), unknown.size()])
	var shown := 0
	for t in unknown:
		if shown < 25:
			print("  low ceiling at %s" % t)
		shown += 1
	if unknown.size() > 0:
		_fail("%d new low-ceiling floor samples" % unknown.size())
