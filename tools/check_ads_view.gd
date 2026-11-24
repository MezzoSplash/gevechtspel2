extends Node
## #362: does the aim mode actually look right? For every weapon it puts the gun in its own ADS pose and
## measures two things in screen pixels: where the sight lines up (it has to sit on the centre of the
## screen) and how close the closest piece of the model comes to that centre (a gun that covers the middle
## hides the target). Weapons without ADS must say so in their .tres and must not move at all.
##   godot --headless --path . res://tools/check_ads_view.tscn
const SIGHT_DX_PX := 3.0 # the sight may sit this far beside the centre
const SIGHT_DY_PX := 14.0 # and this far above or below it (it belongs just under the eye line)
const CLEAR_PX := 5.0 # no part of the model may come closer than this to the centre

var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var pawn := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	pawn.peer_id = -1
	pawn.is_bot = false
	pawn.set_physics_process(false)
	add_child(pawn)
	var cam := pawn.camera
	cam.make_current()
	# Aim through the real path: the zoom key held and the mouse captured, or _update_ads turns it off
	# every tick and the camera drops back to the hip FOV.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("zoom")
	for i in 3:
		await get_tree().physics_frame
	# Angles instead of unproject_position: in a headless run the viewport a camera projects into and the
	# window are not the same size, and half the window would put a fixed offset in every measurement.
	var px_per_rad := (648.0 * 0.5) / tan(deg_to_rad(70.0) * 0.5)
	var ads_count := 0
	for d in Weapon.LOADOUT:
		var def := d as WeaponDef
		# The weapon re-reads its def from the armory every tick, so it goes on per weapon here.
		pawn.weapon.def = def
		pawn.weapon.slots = [def]
		pawn.weapon._active_index = 0
		pawn.weapon._apply_view_for_def()
		var has := def.has_ads()
		# Give the sights their own time to come up, then measure what the player actually sees.
		await get_tree().create_timer(maxf(def.ads_time, 0.05) + 0.25).timeout
		var model: Node3D = pawn.weapon._current_model()
		if not has:
			var rest_ok := pawn.weapon.position.is_equal_approx(pawn.weapon._view_rest)
			_ok(def.ads_mode == 0 and def.ads_fov <= 0.0 and rest_ok,
				"%s: bewust geen ADS (ads_mode NONE), vizierbeeld ongewijzigd" % def.id)
			continue
		ads_count += 1
		if def.is_scope():
			# A scope hides the model and draws the scope picture in the HUD; there is no sight to line up.
			_ok(def.ads_hides_model, "%s: scope verbergt het model en tekent het vizier in de HUD" % def.id)
			continue
		var sight := model.find_child("Sight", true, false) as Node3D if model else null
		var sight_px := Vector2(-999, -999)
		if sight:
			sight_px = _screen_offset(cam, sight.global_position, px_per_rad)
		var near := _closest_vertex_px(model, cam, px_per_rad)
		var line_ok := sight != null and absf(sight_px.x) <= SIGHT_DX_PX and absf(sight_px.y) <= SIGHT_DY_PX
		_ok(line_ok, "%s: vizier op het midden (dx %+.1f px, dy %+.1f px; max %0.0f / %0.0f) fov %.0f" % [
			def.id, sight_px.x, sight_px.y, SIGHT_DX_PX, SIGHT_DY_PX, def.ads_fov])
		_ok(near >= CLEAR_PX, "%s: midden vrij (dichtstbijzijnde modelpunt %.1f px van het midden, min %.0f)" % [
			def.id, near, CLEAR_PX])
	Input.action_release("zoom")
	_ok(ads_count == 7, "%d wapens met ADS (sniper, smg, lmg, rifle, pistol, revolver, slug)" % ads_count)
	print("ADS VIEW CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## The closest a vertex of the gun in hand comes to the centre of the screen, in pixels. Vertices only:
## a coarse but honest test that the barrel is not lying across the crosshair.
## Where a world point lands relative to the middle of the screen, in pixels (y down).
func _screen_offset(cam: Camera3D, world: Vector3, px_per_rad: float) -> Vector2:
	var to: Vector3 = (world - cam.global_position).normalized()
	var b := cam.global_transform.basis
	return Vector2(to.dot(b.x), -to.dot(b.y)) * px_per_rad


func _closest_vertex_px(model: Node3D, cam: Camera3D, px_per_rad: float) -> float:
	if model == null:
		return 0.0
	var best := INF
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		# The sights belong on the eye line (you aim through them); the rest of the gun does not.
		if mi.name.to_lower().contains("sight"):
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				var off := _screen_offset(cam, mi.global_transform * v, px_per_rad)
				best = minf(best, off.length())
	return best
