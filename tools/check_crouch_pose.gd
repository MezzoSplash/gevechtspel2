extends Node
## #164 part 2 headless: the crouch pose bends, it does not squash. On a bot: standing legs are nearly
## straight, crouched knees bend forward and the hips drop, the torso leans instead of the old 0.62
## squash, head/HeadHit stay on Player's head heights, the hands stay on the gun, and a half crouch lies
## between both poses (smooth blend). Optional screenshot: -- shot=/path.png (needs a display).
##   godot --headless --path . res://tools/check_crouch_pose.tscn   → "CROUCH POSE CHECK OK"
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
	menu.set_match_choice(&"quay", Game.MODE_TDM)
	for b in menu._bot_boxes:
		b.value = 1
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and Game.player_for_peer(1):
			break
	var bot: Player = null
	for n in get_tree().get_nodes_in_group("player"):
		if n is Player and n.is_bot:
			bot = n
	var body := bot.body_mesh
	Player.pose_body(body, 0.0)
	var legs := body.get_node_or_null("Legs") as Node3D
	_ok(legs != null and legs.get_child_count() == 6, "bot has legs (thigh, shin, foot ×2)")
	var torso := body.get_node("Torso") as Node3D
	var knee_stand := BodyPose.knee_point(Vector3(0.12, 0.40, 0), Vector3(0.12, 0.055, 0))
	_ok(absf(knee_stand.z) < 0.2, "standing: legs nearly straight (knee %.2f m forward)" % -knee_stand.z)
	var hip_y_stand := torso.position.y - BodyPose.TORSO_H * 0.5
	Player.pose_body(body, 1.0)
	var knee := BodyPose.knee_point(Vector3(0.12, BodyPose.HIP_CROUCH.y, BodyPose.HIP_CROUCH.z), Vector3(0.12, 0.055, 0))
	_ok(knee.z < BodyPose.HIP_CROUCH.z - 0.1 and knee.y > BodyPose.HIP_CROUCH.y, "crouched: knees bend forward and up (%s)" % str(knee))
	_ok(torso.rotation.x < -0.3 and torso.scale.y > 0.7, "torso leans (%.0f deg) instead of the old 0.62 squash (%.2f)" % [rad_to_deg(-torso.rotation.x), torso.scale.y])
	_ok(is_equal_approx((body.get_node("HeadHit") as Node3D).position.y, Player.HEAD_CROUCH_Y), "HeadHit stays on HEAD_CROUCH_Y")
	_ok(is_equal_approx((body.get_node("HeadMesh") as Node3D).position.y, Player.HEAD_CROUCH_Y), "head mesh on the hit target")
	Player.pose_body(body, 0.5)
	var half := torso.position.y
	Player.pose_body(body, 1.0)
	var low := torso.position.y
	_ok(half < hip_y_stand + BodyPose.TORSO_H * 0.5 and half > low, "half crouch lies between both poses")
	# Hands still on the gun while crouched (the camera/gun drops with the head).
	bot.set_physics_process(false) # freeze the bot AI so it does not stand back up
	bot.crouch = 1.0
	bot.head.position.y = Player.CROUCH_EYE
	Player.pose_body(body, 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var arms := body.get_node("Arms") as BodyArms
	var t := arms.hand_targets()
	var worst := 0.0
	for i in 2:
		worst = maxf(worst, (arms._hands[i].position as Vector3).distance_to(t[i]))
	_ok(worst < 0.03, "crouched: hands on the gun (off by %.3f m)" % worst)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			var me := Game.player_for_peer(1)
			me.global_position = bot.global_position + bot.global_transform.basis.x * 2.4 + Vector3(0, 0, 0)
			me.look_at(bot.global_position + Vector3(0, 0.6, 0), Vector3.UP)
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(5))
	print("CROUCH POSE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
