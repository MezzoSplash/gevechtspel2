extends Node
## #164 headless: the pawn's arms reach the gun. For every gun: both hands sit within a few cm of
## their grip/foregrip targets, the elbows stay below the shoulders, the old static arm boxes are
## hidden, and the local pawn has first-person arms. Optional screenshot: shot=/path.png (needs a GPU).
##   godot --headless --path . res://tools/check_arms.tscn   → "ARMS CHECK OK"
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
	var me := Game.player_for_peer(1)
	_ok(me.camera.get_node_or_null("ViewArms") != null, "local pawn has first-person arms")
	var bot: Player = null
	for n in get_tree().get_nodes_in_group("player"):
		if n is Player and n.is_bot:
			bot = n
	var arms := bot.body_mesh.get_node_or_null("Arms") as BodyArms
	_ok(arms != null, "bot has third-person arms")
	_ok(not (bot.body_mesh.get_node("ArmL") as Node3D).visible, "old static arm boxes hidden")
	for w in Weapon.LOADOUT:
		bot.weapon.set_slots([w.id])
		await get_tree().process_frame
		await get_tree().process_frame
		var t := arms.hand_targets()
		var worst := 0.0
		var elbows_ok := true
		for i in 2:
			worst = maxf(worst, (arms._hands[i].position as Vector3).distance_to(t[i]))
			var sh: Vector3 = arms.shoulders[i]
			var el: Vector3 = (arms._upper[i].position as Vector3) * 2.0 - sh
			elbows_ok = elbows_ok and el.y <= maxf(sh.y, t[i].y) + 0.01
			print("    %s %s reach %.2f" % [w.id, ["L", "R"][i], sh.distance_to(t[i])])
		_ok(worst < 0.03, "%s: hands on the gun (off by %.3f m)" % [w.id, worst])
		_ok(elbows_ok, "%s: elbows bend down, not up" % w.id)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			me.global_position = bot.global_position + bot.global_transform.basis.z * -2.2 + Vector3(0.8, 0, 0)
			me.look_at(bot.global_position, Vector3.UP)
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(5))
	print("ARMS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
