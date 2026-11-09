extends Node
## #205: a landing roll was invisible to everyone but the rolling player. The killcam recorded yaw +
## head pitch only, and the body had no "flip" channel at all, so a player who rolled to their death
## stood upright in the replay.
##   godot --headless res://tools/check_killcam_roll.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	# 1) The pawn's flip is a full forward turn across the roll and 0 outside it.
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 2
	Game.bot_count = 2
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	# The pawn is spawned by the match, not by the button: poll instead of guessing a wait.
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.body_mesh != null:
			break
	if me == null or me.body_mesh == null:
		print("  FAIL no local pawn")
		print("KILLCAM ROLL CHECK: FAIL (1 failures)")
		get_tree().quit(1)
		return
	me._roll_t = 0.0
	_ok(is_equal_approx(me.roll_flip(), 0.0), "no roll, no flip")
	var half := Player.ROLL_TIME * 0.5
	me._roll_t = half
	var mid := me.roll_flip()
	_ok(absf(mid) > 1.0, "halfway through a roll the body is tilted (%.2f rad)" % mid)
	me._roll_t = Player.ROLL_TIME * 0.1
	var late := me.roll_flip()
	_ok(absf(late) > absf(mid), "the flip keeps turning as the roll runs out (%.2f -> %.2f rad)" % [mid, late])
	me._roll_t = 0.0

	# 2) pose_body hands the flip to the crystal body (that is the wire the killcam ghosts use).
	Player.pose_body(me.body_mesh, 0.0, Player.MOVE_ROLL, 1.25)
	var crystal := CrystalBody.ensure(me.body_mesh)
	_ok(crystal != null and is_equal_approx(crystal.flip, 1.25), "pose_body forwards the flip to the body")

	# 3) BodyPose actually rotates the rig by it: a quarter turn puts the figure's up axis forward.
	var flat := BodyPose.solve({"crouch": 0.0, "head_y": 1.52, "flip": 0.0})
	var turned := BodyPose.solve({"crouch": 0.0, "head_y": 1.52, "flip": PI * 0.5})
	var flat_up: Vector3 = (flat["torso"] as Transform3D).basis.y
	var turned_up: Vector3 = (turned["torso"] as Transform3D).basis.y
	var angle := rad_to_deg(flat_up.angle_to(turned_up))
	_ok(absf(angle - 90.0) < 2.0, "a quarter-turn flip tilts the body by %.1f deg" % angle)

	# 4) A remote pawn gets the roll from the synced move_fx (#236): it never ticks the roll timer itself.
	me._roll_t = 0.0
	me.apply_network_pose(me.global_position, me.rotation.y, 0.0, [0.0, Player.MOVE_ROLL])
	# The timer starts at the beginning of the roll, so the flip is 0 on that frame and grows from there.
	# The flip eases in, so measure a third of the way through the 0.55 s roll rather than on frame one.
	for i in 20:
		await get_tree().physics_frame
	_ok(absf(me.roll_flip()) > 0.5, "a remote pawn with synced MOVE_ROLL runs the flip locally (%.2f rad)" % me.roll_flip())
	me.apply_network_pose(me.global_position, me.rotation.y, 0.0, [0.0, Player.MOVE_NONE])
	me._roll_t = 0.0

	# 5) The killcam snapshot carries it as the eighth field.
	Game.killcam._frames.clear()
	Game.killcam._snapshot()
	var stored := false
	for f in Game.killcam._frames:
		var pawns: Dictionary = f[1]
		for peer in pawns:
			if int(peer) == me.peer_id:
				var s: Array = pawns[peer]
				stored = s.size() == 10
				if stored:
					_ok(is_equal_approx(float(s[7]), me.roll_flip()), "the snapshot stores the flip")
					_ok(is_equal_approx(float(s[8]), me.throw_amt()), "and the knife-throw pose next to it")
					_ok(is_equal_approx(float(s[9]), me.reload_amt()), "and the reload progress")
	_ok(stored, "the killcam snapshot has the flip field")

	print("KILLCAM ROLL CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
