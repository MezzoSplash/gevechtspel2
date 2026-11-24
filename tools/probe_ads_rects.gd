extends Node
## #377: which mesh is the black bar in the SMG's ADS view? Puts the gun in the aim pose and projects the
## eight corners of every mesh's AABB to screen pixels, so the mesh whose rectangle covers the middle of
## the screen can be named instead of guessed.
##   godot --headless --path . res://tools/probe_ads_rects.tscn -- [weapon_id]
## Screen size for the numbers: the 720p reference the issue uses (centre 640,360) is scaled to the
## viewport the camera projects into; the centre and the ring are reported in that same space.
const REF := Vector2(1280, 720)

var _pawn: Player
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var want := StringName(args[0]) if args.size() > 0 else &"smg"
	_pawn = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	_pawn.peer_id = -1
	_pawn.is_bot = false
	_pawn.set_physics_process(false)
	add_child(_pawn)
	_cam = _pawn.camera
	_cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("zoom")
	var def: WeaponDef = null
	for d in Weapon.LOADOUT:
		if (d as WeaponDef).id == want:
			def = d as WeaponDef
	if def == null:
		print("PROBE: onbekend wapen %s" % want)
		get_tree().quit(1)
		return
	_pawn.weapon.def = def
	_pawn.weapon.slots = [def]
	_pawn.weapon._active_index = 0
	_pawn.weapon._apply_view_for_def()
	await get_tree().create_timer(maxf(def.ads_time, 0.05) + 0.3).timeout
	var vp: Vector2 = _cam.get_viewport().get_visible_rect().size
	var scale := REF / vp
	var centre := REF * 0.5
	print("PROBE %s: ads=%s fov=%.0f viewport=%s (schaal naar 720p: %.2f,%.2f)" % [
		def.id, str(_pawn.weapon._ads), _cam.fov, str(vp), scale.x, scale.y])
	var model: Node3D = _pawn.weapon._current_model()
	if model == null:
		print("PROBE: geen model")
		get_tree().quit(1)
		return
	var rows: Array = []
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		var r := Rect2()
		var first := true
		for i in 8:
			var corner := box.get_endpoint(i)
			var px := _cam.unproject_position(corner) * scale
			if first:
				r = Rect2(px, Vector2.ZERO)
				first = false
			else:
				r = r.expand(px)
		var covers := r.has_point(centre)
		rows.append({"name": mi.name, "rect": r, "covers": covers, "near_px": _dist_to_centre(r, centre)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["near_px"]) < float(b["near_px"]))
	for r in rows:
		var rect: Rect2 = r["rect"]
		print("  %-22s x %.0f..%.0f  y %.0f..%.0f  %s%s" % [str(r["name"]), rect.position.x, rect.end.x,
			rect.position.y, rect.end.y, "MIDDEN" if bool(r["covers"]) else "",
			"  (dichtstbij %.0f px)" % float(r["near_px"]) if float(r["near_px"]) < 200.0 else ""])
	Input.action_release("zoom")
	get_tree().quit(0)


## Distance from the centre to the rectangle (0 when the centre is inside).
func _dist_to_centre(r: Rect2, c: Vector2) -> float:
	if r.has_point(c):
		return 0.0
	var dx := maxf(maxf(r.position.x - c.x, 0.0), c.x - r.end.x)
	var dy := maxf(maxf(r.position.y - c.y, 0.0), c.y - r.end.y)
	return Vector2(dx, dy).length()
