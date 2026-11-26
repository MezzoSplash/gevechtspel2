extends Node
## #381: renders the killcam with ADS, the sniper scope and a grapple rope, so a human can judge them.
## Not part of run_checks.sh (it needs a real screen): xvfb-run -a godot --path . res://tools/shot_killcam_ads.tscn -- --out /tmp
var out := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and not Game.play_locked() and Game._round_active:
			break
	if me == null:
		print("SHOT ADS: no round")
		get_tree().quit(1)
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	var kc: Killcam = Game.killcam
	# A few real snapshots so the ghosts stand on the real map at real poses.
	for i in 40:
		kc._process(1.0 / 30.0)
	var other := 0
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p != null and p != me and not p.is_dead:
			other = p.peer_id
			break
	var rifle := _index_of(&"rifle")
	var sniper := _index_of(&"sniper")
	main.get_node("CanvasLayer").visible = false

	# 1) Rifle, aiming down the sights.
	_play(kc, me.peer_id, other, rifle, 1.0, false)
	await _grab(kc, 1.4, "%s/killcam_rifle_ads.png" % out)
	kc._end_playback()

	# 2) Sniper, scoped: the model goes away and the scope is drawn.
	_play(kc, me.peer_id, other, sniper, 1.0, false)
	await _grab(kc, 1.4, "%s/killcam_sniper_scope.png" % out)
	kc._end_playback()

	# 3) Hip, with a grapple rope from the other pawn to an anchor in front of the camera.
	_play(kc, me.peer_id, other, rifle, 0.0, true)
	await _grab(kc, 1.4, "%s/killcam_grapple.png" % out)
	kc._end_playback()
	print("SHOT ADS: done")
	get_tree().quit()


func _index_of(id: StringName) -> int:
	for i in Weapon.LOADOUT.size():
		if Weapon.LOADOUT[i].id == id:
			return i
	return 0


## A clip from the recorder's own frames, with the killer's weapon/aim and the other pawn's rope set.
func _play(kc: Killcam, killer: int, victim: int, wi: int, ads: float, rope: bool) -> void:
	var frames: Array = []
	for f in kc._frames:
		var t: float = f[0]
		var pawns: Dictionary = (f[1] as Dictionary).duplicate(true)
		if pawns.has(killer):
			var s: Array = pawns[killer]
			if s.size() >= 10:
				s[4] = wi
				s[10] = ads
		if pawns.has(killer) and (pawns[killer] as Array).size() >= 12:
			# The rope on the killer, so it runs out of the camera's own hand: the shot has to show it.
			var ks: Array = pawns[killer]
			var at: Vector3 = ks[0]
			var fwd := Vector3(-sin(float(ks[1])), 0.0, -cos(float(ks[1]))) # the pawn looks down -Z
			ks[11] = rope
			ks[12] = at + fwd * 11.0 + Vector3(0.0, 4.5, 0.0)
		frames.append([t, pawns, f[2], f[3]])
	if frames.size() < 3:
		return
	var t_kill := float(frames[frames.size() - 1][0]) - 0.2
	kc._clips[victim] = {"t_kill": t_kill, "frames": frames, "events": [], "meta": kc._meta.duplicate(true)}
	kc.play_final({"k": killer, "v": victim, "kt": 0, "vt": 1, "kn": "SHOT", "vn": "BOT", "w": "rifle"})


## Let the replay run to `at` seconds of wall clock, then save the frame.
func _grab(kc: Killcam, at: float, path: String) -> void:
	var guard := 0
	while kc.is_playing() and kc._real_t < at and guard < 900:
		guard += 1
		kc._process(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())
