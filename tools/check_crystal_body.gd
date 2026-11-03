extends Node
## #164 B1 crystal body, headless: the pose driver (BodyPose via CrystalBody) on a live bot.
## Crouch lowers and leans the torso and spreads the feet, dive lays the body flat with the feet behind,
## a wall run tilts the top away from the wall and puts the wall-side hand near it, a jump tucks the
## feet, walking moves them, HeadHit keeps Player's head heights, no arm/leg meshes are left, a killcam
## copy of the template body gets a crystal body, and a dedicated server builds nothing.
## Screenshots (needs a display): -- shots=/dir  → b1_{idle,crouch,wallrun,dive}_{blue,orange}.png
##   godot --headless --path . res://tools/check_crystal_body.tscn   → "CRYSTAL BODY CHECK OK"
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
	var bots: Array[Player] = []
	for n in get_tree().get_nodes_in_group("player"):
		if n is Player and n.is_bot:
			bots.append(n)
			n.set_physics_process(false) # freeze the AI; this check drives the pose
	var bot := bots[0]
	var body := bot.body_mesh
	var c := body.get_node_or_null("Crystal") as CrystalBody
	_ok(c != null and c.hands != null, "bot has a crystal body with floating hands")
	for n in ["ArmL", "ArmR", "Arms", "Legs"]:
		_ok(body.get_node_or_null(n) == null, "no old %s node" % n)
	_ok(Game.player_for_peer(1).camera.get_node_or_null("ViewHands") != null, "local pawn has first-person crystal hands")

	var stand := _pose(c, 0.0, Player.MOVE_NONE)
	var torso := body.get_node("Torso") as Node3D
	var t_stand := torso.position
	var f_stand := _feet_x(c)
	_pose(c, 1.0, Player.MOVE_NONE)
	_ok(torso.position.y < t_stand.y - 0.4, "crouch: torso lowered (%.2f → %.2f)" % [t_stand.y, torso.position.y])
	_ok((torso.basis * Vector3.UP).z < -0.4, "crouch: torso leans forward")
	_ok(_feet_x(c) > f_stand + 0.1, "crouch: feet spread (%.2f → %.2f)" % [f_stand, _feet_x(c)])
	_ok(is_equal_approx((body.get_node("HeadHit") as Node3D).position.y, Player.HEAD_CROUCH_Y), "HeadHit on HEAD_CROUCH_Y")
	_ok(_hands_on_gun(c) < 0.03, "crouch: hands on the gun (off by %.3f m)" % _hands_on_gun(c))
	_pose(c, 0.0, Player.MOVE_NONE)
	_ok(is_equal_approx((body.get_node("HeadHit") as Node3D).position.y, Player.HEAD_STAND_Y), "HeadHit back on HEAD_STAND_Y")
	_ok(_hands_on_gun(c) < 0.03, "stand: hands on the gun (off by %.3f m)" % _hands_on_gun(c))

	var dive := BodyPose.solve({"crouch": 1.0, "head_y": Player.HEAD_CROUCH_Y, "dive": 1.0})
	var d_up := (dive["torso"] as Transform3D).basis * Vector3.UP
	_ok(absf(d_up.y) < 0.35, "dive: torso near horizontal (up.y %.2f)" % d_up.y)
	_ok((dive["feet"][0] as Transform3D).origin.z > 0.3, "dive: feet trail behind")
	var wall := BodyPose.solve({"head_y": Player.HEAD_STAND_Y, "wall": 1.0, "walk": 1.0})
	_ok(((wall["torso"] as Transform3D).basis * Vector3.UP).x < -0.2, "wall run (wall right): top tilts away")
	var fx := ((wall["feet"][0] as Transform3D).origin.x + (wall["feet"][1] as Transform3D).origin.x) * 0.5
	_ok(fx > 0.1, "wall run: feet toward the wall (%.2f)" % fx)
	var air := BodyPose.solve({"head_y": Player.HEAD_STAND_Y, "air": 1.0})
	_ok((air["feet"][0] as Transform3D).origin.y > 0.2, "air: feet tucked up")
	var w0 := BodyPose.solve({"head_y": 1.52, "walk": 1.0, "phase": 0.0})
	var w1 := BodyPose.solve({"head_y": 1.52, "walk": 1.0, "phase": PI / 2})
	_ok((w0["feet"][0] as Transform3D).origin.distance_to((w1["feet"][0] as Transform3D).origin) > 0.1, "walk: feet step")

	# Wall-run hand: a wall right of the bot, the right hand reaches it.
	var wall_body := _make_wall(bot, 1.0)
	await get_tree().physics_frame
	await _settle(c, 0.0, Player.MOVE_WALLRUN)
	var wp := c.global_transform * c.hands.hand_position(1)
	var wall_x := (bot.global_transform.affine_inverse() * wp).x
	_ok(wall_x > 0.4 and wall_x < 0.62, "wall run: right hand next to the wall at 0.65 (%.2f)" % wall_x)
	wall_body.queue_free()
	await _settle(c, 0.0, Player.MOVE_NONE)

	bot.apply_network_pose(bot.global_position, bot.rotation.y, 0.0, [1.0, Player.MOVE_DIVE])
	_ok(bot.move_fx == Player.MOVE_DIVE and is_equal_approx(bot.crouch, 1.0) and c.move_fx == Player.MOVE_DIVE, "client bot: synced stance reaches the body")
	bot.apply_network_pose(bot.global_position, bot.rotation.y, 0.0, [0.0, Player.MOVE_NONE])
	_ok(bot.weapon.position.z > bot.weapon._rest_pos.z, "third-person gun pulled toward the body")
	var tmpl := (load("res://scenes/player.tscn") as PackedScene).instantiate()
	var ghost := (tmpl.get_node("BodyMesh") as Node3D).duplicate() as Node3D
	tmpl.free()
	add_child(ghost)
	Player.pose_body(ghost, 0.5)
	_ok(ghost.get_node_or_null("Crystal") is CrystalBody, "killcam copy of the template body gets a crystal body")
	ghost.queue_free()
	Game.is_dedicated = true
	var srv := Node3D.new()
	add_child(srv)
	_ok(CrystalBody.ensure(srv) == null and srv.get_child_count() == 0, "dedicated server: no meshes")
	Game.is_dedicated = false
	srv.queue_free()

	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			await _shots(main, bots, a.substr(6))
	print("CRYSTAL BODY CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _pose(c: CrystalBody, k: float, fx: int) -> Dictionary:
	Player.pose_body(c.get_parent(), k, fx)
	c.tick(0.0) # 0 s step: jump straight to the targets
	c.hands._process(0.0)
	return {}


func _settle(c: CrystalBody, k: float, fx: int) -> void:
	for i in 40:
		Player.pose_body(c.get_parent(), k, fx)
		await get_tree().process_frame


func _feet_x(c: CrystalBody) -> float:
	return absf(c._feet[0].position.x) + absf(c._feet[1].position.x)


func _hands_on_gun(c: CrystalBody) -> float:
	var t := c.hands.hand_targets()
	return maxf(c.hands.hand_position(0).distance_to(t[0]), c.hands.hand_position(1).distance_to(t[1]))


func _make_wall(p: Player, side: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 3.0, 4.0)
	cs.shape = box
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	sb.add_child(mi)
	p.get_parent().add_child(sb)
	sb.global_transform = Transform3D(p.global_basis, p.global_transform * Vector3(side * 0.70, 1.2, 0))
	return sb


## Large framed shots of each pose per team, without HUD or class-select overlay.
func _shots(main: Node, bots: Array[Player], dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for cl in main.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 44
	add_child(cam)
	cam.current = true
	var b := bots[0]
	b.set_process(false) # keeps the nametag hidden
	b.nametag.visible = false
	for team_i in 2:
		b.team_id = team_i
		b._apply_team_visual()
		var team := "blue" if team_i == 0 else "orange"
		var c := b.body_mesh.get_node("Crystal") as CrystalBody
		for pose in ["idle", "crouch", "wallrun", "dive"]:
			var wall: StaticBody3D = _make_wall(b, 1.0) if pose == "wallrun" else null
			var fx := {"wallrun": Player.MOVE_WALLRUN, "dive": Player.MOVE_DIVE}.get(pose, Player.MOVE_NONE) as int
			var k := 1.0 if pose in ["crouch", "dive"] else 0.0
			b.head.position.y = lerpf(Player.STAND_EYE, Player.CROUCH_EYE, k)
			await get_tree().physics_frame
			await _settle(c, k, fx)
			var focus := b.global_transform * Vector3(0, 0.85 if k < 0.5 else 0.6, 0)
			var eye := b.global_transform * Vector3(-1.7, 1.25, -2.1)
			cam.look_at_from_position(eye, focus, Vector3.UP)
			await get_tree().create_timer(0.2).timeout
			get_viewport().get_texture().get_image().save_png("%s/b1_%s_%s.png" % [dir, pose, team])
			if wall:
				wall.queue_free()
