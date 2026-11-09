extends Node
## #164: a procedural reload that is timed on the weapon's own reload_time, in the viewmodel and on the
## body (third person / killcam).
##   godot --headless res://tools/check_reload_anim.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 2
	Game.bot_count = 2
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and me.body_mesh != null:
			break
	if me == null or me.weapon == null or me.body_mesh == null:
		print("  FAIL no local pawn with a weapon")
		print("RELOAD ANIM CHECK: FAIL (1 failures)")
		get_tree().quit(1)
		return
	var w := me.weapon

	# 1) Idle: no progress, no dip.
	_ok(is_equal_approx(w.reload_anim(), 0.0), "no reload, no progress")
	_ok(is_equal_approx(w._reload_dip.length(), 0.0), "no reload, no dip")

	# 2) Mid-reload: progress climbs, the viewmodel tilts and dips.
	w.ammo = maxi(w.def.mag_size - 3, 0) # _start_reload() refuses a full magazine
	w._start_reload()
	await get_tree().create_timer(0.05).timeout
	var early := w.reload_anim()
	_ok(early > 0.0 and early < 0.5, "the progress starts at %.2f" % early)
	for i in 200:
		await get_tree().physics_frame
		if w.reload_anim() > 0.45:
			break
	var mid := w.reload_anim()
	_ok(mid > 0.3 and mid < 0.8, "halfway through the reload is %.2f" % mid)
	_ok(absf(w.rotation.x) > 0.1, "the viewmodel tilts (%.2f rad)" % w.rotation.x)
	_ok(w._reload_dip.length() > 0.01, "the viewmodel dips (%.3f m)" % w._reload_dip.length())

	# 3) The body gets the same progress, and its pose answers to it.
	_ok(is_equal_approx(me.reload_amt(), w.reload_anim()), "the pawn forwards the weapon's progress")
	Player.pose_body(me.body_mesh, 0.0, Player.MOVE_NONE, 0.0, 0.0, 0.5)
	var crystal := CrystalBody.ensure(me.body_mesh)
	_ok(crystal != null and is_equal_approx(crystal.reload_amt, 0.5), "pose_body forwards the reload to the body")
	var idle := BodyPose.solve({"crouch": 0.0, "head_y": 1.52, "reload": 0.0})
	var loaded := BodyPose.solve({"crouch": 0.0, "head_y": 1.52, "reload": 0.5})
	var tilt := rad_to_deg((idle["torso"] as Transform3D).basis.y.angle_to((loaded["torso"] as Transform3D).basis.y))
	_ok(tilt > 3.0, "the torso answers to the reload (%.1f deg at half)" % tilt)
	_ok((loaded["torso"] as Transform3D).origin.y < (idle["torso"] as Transform3D).origin.y,
		"and settles down while the mag is out")

	# 4) It ends clean: progress back to 0 once the reload completes.
	for i in 400:
		await get_tree().physics_frame
		if w.reload_anim() <= 0.0:
			break
	_ok(is_equal_approx(w.reload_anim(), 0.0), "the progress returns to 0 when the magazine is in")

	print("RELOAD ANIM CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
