extends Node
## #164 / #252: a procedural reload that is timed on the weapon's own reload_time, in the viewmodel and
## on the body (third person / killcam) — and since #252 four real styles instead of one tilt.
##   godot --headless res://tools/check_reload_anim.tscn
var fails := 0
## The three progress points the spec samples the styles at.
const SAMPLES: Array[float] = [0.25, 0.5, 0.75]


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


## #252, part 1: the data. Every gun names a real style, every style turns the gun and moves the hand
## far enough that the movement is visible, and the four are not the same curve please.
func _data() -> void:
	for d in Weapon.LOADOUT:
		_ok(ReloadAnims.STYLES.has(d.reload_style), "%s plays a real style (%s)" % [d.id, d.reload_style])
	for style in ReloadAnims.STYLES:
		var max_rot := 0.0
		var max_hand := 0.0
		var step := 0
		while step <= 18:
			var t := 0.05 + 0.05 * float(step)
			step += 1
			var s := ReloadAnims.solve(style, t, 6, true)
			max_rot = maxf(max_rot, (s.rot as Vector3).length())
			max_hand = maxf(max_hand, ((s.hand as Vector3) - ReloadAnims.HAND_REST).length())
		_ok(max_rot >= ReloadAnims.MIN_ROT, "%s turns the gun at least %.1f rad (%.2f)" % [style, ReloadAnims.MIN_ROT, max_rot])
		_ok(max_hand >= ReloadAnims.MIN_HAND, "%s moves the hand at least %.2f m (%.3f)" % [style, ReloadAnims.MIN_HAND, max_hand])
	for t in SAMPLES:
		var closest_rot := 99.0
		var closest_hand := 99.0
		for i in ReloadAnims.STYLES.size():
			for j in range(i + 1, ReloadAnims.STYLES.size()):
				var a := ReloadAnims.solve(ReloadAnims.STYLES[i], t, 6, true)
				var b := ReloadAnims.solve(ReloadAnims.STYLES[j], t, 6, true)
				var drot := ((a.rot as Vector3) - (b.rot as Vector3)).length()
				var dhand := ((a.hand as Vector3) - (b.hand as Vector3)).length()
				closest_rot = minf(closest_rot, drot)
				closest_hand = minf(closest_hand, dhand)
		_ok(closest_rot > 0.05 or closest_hand > 0.02,
			"at t=%.2f all four styles play differently (closest pair: %.2f rad, %.3f m)" % [t, closest_rot, closest_hand])
	_ok(int(ReloadAnims.solve(ReloadAnims.SHELLS, 0.5, 6).loops) == 6, "an empty 6-round tube gets 6 insert loops")
	_ok(int(ReloadAnims.solve(ReloadAnims.SHELLS, 0.5, 2).loops) == 2, "and two missing rounds get 2")


func _ready() -> void:
	_data()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 1
	Game.bot_count = 1
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	# Wait for the round itself: a reload started during the round-start freeze is cancelled by the
	# respawn that ends it, which would make this check flaky.
	var me: Player = null
	for i in 900:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and me.body_mesh != null and not Game.play_locked() and Game._round_active:
			break
	# The round start respawns the pawn: take the one that is actually simulating now.
	me = Game.player_for_peer(multiplayer.get_unique_id())
	if me == null or me.weapon == null or me.body_mesh == null:
		print("  FAIL no local pawn with a weapon")
		print("RELOAD ANIM CHECK: FAIL (1 failures)")
		get_tree().quit(1)
		return
	var w := me.weapon
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	me._spawn_protect = 999.0

	# 1) Idle: no progress, no dip.
	_ok(is_equal_approx(w.reload_anim(), 0.0), "no reload, no progress")
	_ok(is_equal_approx(w._reload_dip.length(), 0.0), "no reload, no dip")

	# 2) Mid-reload: progress climbs, the viewmodel takes the style's own pose and the hand shows.
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
	_ok(w.rotation.length() > ReloadAnims.MIN_ROT, "the viewmodel takes its style's pose (%.2f rad)" % w.rotation.length())
	_ok(w._reload_dip.length() > 0.01, "the viewmodel moves (%.3f m)" % w._reload_dip.length())
	var hands := w.view_hands()
	_ok(hands != null, "the pawn has first-person hands to carry the reload")
	if hands != null:
		_ok(float(hands.reach[0][1]) > 0.5, "the left hand leaves the gun while reloading (weight %.2f)" % float(hands.reach[0][1]))
		var foregrip := hands.hand_targets()[0]
		_ok((hands.hand_position(0) - foregrip).length() > 0.08,
			"and travels to the mag (%.3f m off the foregrip)" % (hands.hand_position(0) - foregrip).length())
	var rifle_mid_rot := w.rotation.length()

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

	# 4) It ends clean: progress back to 0 once the reload completes, and the hand leaves.
	for i in 400:
		await get_tree().physics_frame
		if w.reload_anim() <= 0.0:
			break
	await get_tree().physics_frame
	_ok(is_equal_approx(w.reload_anim(), 0.0), "the progress returns to 0 when the magazine is in")
	var done_hands := w.view_hands()
	_ok(done_hands == null or float(done_hands.reach[0][1]) <= 0.001, "the hand goes back to the gun when the reload is done")

	# 5) The shells style counts the rounds the tube is missing, and a shotgun does not reload like a
	# rifle.
	w.set_slots(["shotgun"])
	await get_tree().physics_frame
	_ok(w.def.reload_style == ReloadAnims.SHELLS, "the shotgun plays the shells style (%s)" % w.def.reload_style)
	w.ammo = 2
	w._start_reload()
	_ok(w._reload_shells == w.def.mag_size - 2, "2 of %d rounds left plays %d insert loops" % [w.def.mag_size, w._reload_shells])
	for i in 200:
		await get_tree().physics_frame
		if w.reload_anim() > 0.45:
			break
	_ok(w.reload_anim() > 0.3, "the shotgun reload runs (%.2f)" % w.reload_anim())
	_ok(w.rotation.length() > ReloadAnims.MIN_ROT, "and takes the shells pose (%.2f rad)" % w.rotation.length())
	_ok(not is_equal_approx(w.rotation.length(), rifle_mid_rot), "which is not the rifle's pose (%.2f vs %.2f rad)" % [w.rotation.length(), rifle_mid_rot])

	# 6) #252 part 2: a reload that arrives over the wire. Game.sync_reload is what every other client
	# runs, so driving a bot through it tests the real path: the body reports the reload and its left
	# hand leaves the gun.
	var bot: Player = null
	for n in get_tree().get_nodes_in_group("player"):
		var cand := n as Player
		if cand != null and cand.is_bot and cand.weapon != null:
			bot = cand
			break
	_ok(bot != null, "there is a remote pawn to reload")
	if bot != null:
		var bot_crystal := CrystalBody.ensure(bot.body_mesh)
		Game.sync_reload(bot.peer_id, 2, 1.5) # index 2 is the shotgun: the shells style
		await get_tree().physics_frame
		await get_tree().physics_frame
		_ok(bot.reload_amt() > 0.0 and bot.reload_amt() < 0.3, "the pawn reloads from the sync (%.2f)" % bot.reload_amt())
		_ok(bot.reload_style() == ReloadAnims.SHELLS, "with the style of the gun that was reloaded (%s)" % bot.reload_style())
		for i in 200:
			await get_tree().physics_frame
			if bot.reload_amt() > 0.4:
				break
		var hand_w := float(bot_crystal.hands.reach[0][1]) if bot_crystal != null and bot_crystal.hands != null else 0.0
		_ok(hand_w > 0.3, "and the body's left hand leaves the gun mid-reload (weight %.2f)" % hand_w)
		for i in 200:
			await get_tree().physics_frame
			if bot.reload_amt() <= 0.0:
				break
		_ok(is_equal_approx(bot.reload_amt(), 0.0), "the synced reload ends on its own time")
		if bot.weapon.def.reload_style != ReloadAnims.SHELLS:
			_ok(bot.reload_style() != ReloadAnims.SHELLS, "and the body is back on its own gun's style (%s)" % bot.reload_style())

	print("RELOAD ANIM CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
