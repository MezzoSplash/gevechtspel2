extends Node
## #25: a knife throw had no animation outside the thrower's own viewmodel. Every client now plays the
## body's wind-up and follow-through, triggered by the knife count that already syncs.
##   godot --headless res://tools/check_knife_throw_anim.tscn
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
		if me != null and me.body_mesh != null:
			break
	if me == null or me.body_mesh == null:
		print("  FAIL no local pawn")
		print("KNIFE THROW ANIM CHECK: FAIL (1 failures)")
		get_tree().quit(1)
		return

	# 1) The animation runs and ends on its own.
	me._throw_t = 0.0
	_ok(is_equal_approx(me.throw_amt(), 0.0), "no throw, no lean")
	me.play_throw_anim()
	var mid := me.throw_amt()
	_ok(mid >= 0.0 and me._throw_t > 0.0, "play_throw_anim() starts the flick (%.2f)" % mid)
	for i in 60:
		await get_tree().physics_frame
		if me._throw_t <= 0.0:
			break
	_ok(me._throw_t <= 0.0 and is_equal_approx(me.throw_amt(), 0.0), "the flick ends by itself")

	# 2) Every client learns the throw from the synced knife count dropping, and a refill is silent.
	me._throw_t = 0.0
	me.knives = 3
	Game.sync_knife_count(me.peer_id, 2)
	_ok(me._throw_t > 0.0, "a knife count that drops starts the throw animation")
	me._throw_t = 0.0
	Game.sync_knife_count(me.peer_id, 3)
	_ok(is_equal_approx(me._throw_t, 0.0), "a refill does not")

	# 3) The pose carries it to the body, and the rig actually turns.
	Player.pose_body(me.body_mesh, 0.0, Player.MOVE_NONE, 0.0, 0.7)
	var crystal := CrystalBody.ensure(me.body_mesh)
	_ok(crystal != null and is_equal_approx(crystal.throw_amt, 0.7), "pose_body forwards the throw to the body")
	var rest := BodyPose.solve({"crouch": 0.0, "head_y": 1.52, "throw": 0.0})
	var thrown := BodyPose.solve({"crouch": 0.0, "head_y": 1.52, "throw": 1.0})
	var angle := rad_to_deg((rest["torso"] as Transform3D).basis.y.angle_to((thrown["torso"] as Transform3D).basis.y))
	_ok(angle > 10.0, "a full throw turns the figure by %.1f deg" % angle)

	print("KNIFE THROW ANIM CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
