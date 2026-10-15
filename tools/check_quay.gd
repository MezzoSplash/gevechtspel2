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
	await _surfs()
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
	if n.y > 0.995:
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
		var want: String = p.want
		var got: String
		if want == "sweep":
			got = _sweep(a, b)
		elif want == "strip":
			got = "strip" if _in_strip(b) else "outside every strip"
		else:
			got = _classify(_ray(a, b))
		var ok := got == want
		if want == "slope" and got in ["slope"]:
			ok = true
		if not ok:
			bad += 1
			_fail("probe %s want %s got %s" % [p.name, want, got])
	print("PROBE %d rays, %d bad" % [list.size(), bad])


## 0.3 m sphere cast from a to b: "sweep" when it gets all the way, else where it stopped.
func _sweep(a: Vector3, b: Vector3) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, a)
	q.motion = b - a
	q.collision_mask = 1
	var r := space.cast_motion(q)
	if r.size() == 0 or r[0] >= 1.0:
		return "sweep"
	return "blocked at %s" % (a + (b - a) * r[0]).snapped(Vector3.ONE * 0.01)


## Inside the box of any speed strip (Node3D in group speed_strip; its scale is the box size).
func _in_strip(p: Vector3) -> bool:
	for n in map.find_children("Strip*", "Node3D", true, false):
		if not n.is_in_group("speed_strip"):
			continue
		var t: Transform3D = (n as Node3D).global_transform
		var local := t.affine_inverse() * p
		if absf(local.x) <= 0.5 and absf(local.y) <= 0.5 and absf(local.z) <= 0.5:
			return true
	return false


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


## Rides each surf with a bare capsule: gravity, velocity clipped to the face while touching it
## (the player's surf rule) and a steady push into the face like holding strafe. Prints where it ends up so a run on the old
## and the new map can be compared (map=res://... user arg). Report only, no pass/fail: the
## bare capsule is a much worse surfer than a player.
func _surf(label: String, start: Vector3, vel: Vector3, push: Vector3, secs := 4.0) -> void:
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
	root.add_child(body)
	body.global_position = start
	body.velocity = vel
	var dt := 1.0 / 60.0
	var ride := 0.0
	var top_speed := 0.0
	for f in int(secs * 60):
		body.velocity.y -= 20.0 * dt
		if not body.is_on_floor():
			body.velocity += push * 10.0 * dt # holding strafe into the face
		body.move_and_slide()
		var touching := false
		for i in body.get_slide_collision_count():
			var n := body.get_slide_collision(i).get_normal()
			if n.y >= 0.15 and n.y <= 0.62:
				body.velocity = body.velocity - n * body.velocity.dot(n)
				touching = true
		if touching:
			ride += dt
		top_speed = maxf(top_speed, Vector2(body.velocity.x, body.velocity.z).length())
		await physics_frame
		if body.is_on_floor() and f > 10:
			break
	var endp := body.global_position
	body.queue_free()
	print("SURF %-10s ride %.2f s, top %.1f m/s, end %s" % [label, ride, top_speed, endp.snapped(Vector3.ONE * 0.1)])


func _surfs() -> void:
	# Start on the face, 1-1.5 m above the toe, moving downhill. Push = into the face.
	var rides := {
		"flank": [Vector3(-42.47, 10.91, 37.0), Vector3(0, 0, -13), Vector3(-1, 0, 0)],
		"dock": [Vector3(-15.13, 4.57, 11.0), Vector3(0, 0, -11), Vector3(-1, 0, 0)],
		"corner": [Vector3(26.3, 10.83, 26.0), Vector3(0, 0, -11), Vector3(1, 0, 0)],
		"cross": [Vector3(7.5, 2.33, -0.18), Vector3(-11, 0, 0), Vector3(0, 0, 1)],
	}
	for k in rides:
		var r: Array = rides[k]
		await _surf(k + "_b", r[0], r[1], r[2])
		if k == "cross":
			continue # one piece through the middle, it faces orange only
		await _surf(k + "_o", Vector3(-r[0].x, r[0].y, -r[0].z), Vector3(-r[1].x, r[1].y, -r[1].z), Vector3(-r[2].x, r[2].y, -r[2].z))


func _mirror(pts: Array) -> Array:
	var out := []
	for p in pts:
		out.append(Vector3(-p.x, p.y, -p.z))
	return out


func _walks() -> void:
	var routes := {
		# West side lane, blue yard strip to orange yard strip, over the new ramps and under the arch.
		"west_lane": [Vector3(-20, 0, 52), Vector3(-38, 0, 51), Vector3(-38, 0, 41.3), Vector3(-38, 0, 38.5),
			Vector3(-38, 4, 23), Vector3(-40.6, 4, 16), Vector3(-40.6, 4, 10), Vector3(-37, 4, -8), Vector3(-40, 4, -20),
			Vector3(-40, 0, -41), Vector3(-39, 0, -51), Vector3(-20, 0, -52)],
		# Round the inner side of the deck stack, then through the office (west door, north door).
		"deck_inner": [Vector3(-38, 4, 23), Vector3(-29.5, 4, 15.5), Vector3(-29.5, 4, 10), Vector3(-34, 4, 0),
			Vector3(-28, 4, 0), Vector3(-26, 4, -2.5), Vector3(-26, 4, -7), Vector3(-36, 4, -12)],
		# Office: ground floor, up the stair, across the top floor, out of the drop opening onto the deck.
		"office_up": [Vector3(-27, 4, 6.5), Vector3(-26, 4, 3.6), Vector3(-21.55, 4, 3.8),
			Vector3(-21.55, 7.8, -4.0), Vector3(-25.5, 7.8, -4.0), Vector3(-25.5, 7.8, 2.2), Vector3(-21.3, 7.8, 2.2),
			Vector3(-19.0, 4, 2.2)],
		# Along the foot of the flank surf, on the new deck.
		"surf_foot": [Vector3(-41.2, 4, 20), Vector3(-41.2, 4, 5), Vector3(-41.2, 4, -2), Vector3(-43.5, 4, -6)],
		# Quay ramps (deck <-> dock), unchanged, as a regression walk.
		"quay_ramp": [Vector3(-26, 4, 18.1), Vector3(-12, 0, 18.1), Vector3(-8.5, 0, 21.5)],
		# Corner exit landing, west up the kicker to the toe of the dock surf.
		"chain_kicker": [Vector3(-2, 0, 9.5), Vector3(-8, 0, 9.5), Vector3(-14.0, 0, 9.5)],
		# Run-in to the dock surf start: deck, over the ramp top, onto the new pad.
		"dock_entry": [Vector3(-24, 4, 21), Vector3(-20, 4, 15.0), Vector3(-15.4, 4, 14.8)],
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
		"west_office_low": Vector3(-27, 4, 0), "west_office_top": Vector3(-25.5, 7.8, 0),
		"east_office_top": Vector3(25.5, 7.8, 0),
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


## True when there is floor at this height a capsule radius away in all four directions:
## a room or a slot you can stand in, not a window sill or the top of a wall.
func _wide(x: float, fy: float, z: float) -> bool:
	for d in [Vector2(0.45, 0), Vector2(-0.45, 0), Vector2(0, 0.45), Vector2(0, -0.45)]:
		var h := _ray(Vector3(x + d.x, fy + 0.3, z + d.y), Vector3(x + d.x, fy - 0.3, z + d.y))
		if h.is_empty() or absf(h.position.y - fy) > 0.12:
			return false
	return true


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
						if gap > 0.3 and gap < 1.95 and _wide(x, fy, z):
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
