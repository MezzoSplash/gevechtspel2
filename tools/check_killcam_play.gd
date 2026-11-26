extends Node
## #317 stap 2: the replay really builds and plays. `shot_killcam` needs a real kill inside the buffer
## window and often has none (it says "nothing to replay" on main too), so this check feeds the recorder's
## own frames in as a clip and drives the playback: ghosts, viewmodel, overlay, camera, and the teardown.
##   ./run.sh --headless res://tools/check_killcam_play.tscn   → "KILLCAM PLAY CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 3
	Game.bot_count = 3
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and not Game.play_locked() and Game._round_active:
			break
	if me == null:
		print("  FAIL no round started")
		print("KILLCAM PLAY CHECK: FAIL (1 failures)")
		get_tree().quit(1)
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	# Let the rolling buffer fill a little: the clip needs two frames 0.1 s apart.
	# Fill the rolling buffer by hand, with the node's own _process and the deltas the match uses: in
	# headless the engine's delta is useless for a clock of a few seconds, and a check must not depend
	# on the frame rate of the machine it runs on.
	var kc: Killcam = Game.killcam
	for i in 100:
		kc._process(1.0 / 30.0)
	_ok(kc._frames.size() >= 3, "the recorder filled its buffer (%d frames, %.1f s)" % [kc._frames.size(), kc._clock])

	# The clip is made of the recorder's own frames, so the poses, weapons and meta are the real ones.
	var victim := 0
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p != null and p.peer_id != me.peer_id and not p.is_dead:
			victim = p.peer_id
			break
	var frames: Array = kc._frames.duplicate()
	var t_kill := float(frames[frames.size() - 1][0]) - 0.2
	var clip := {"t_kill": t_kill, "frames": frames, "events": [], "meta": kc._meta.duplicate(true)}
	kc._clips[victim] = clip
	var info := {
		"k": me.peer_id, "v": victim, "kt": 0, "vt": 1, "kn": "CHECK", "vn": "BOT",
		"w": "rifle", "hs": false,
	}
	main.get_node("CanvasLayer").visible = false
	kc.play_final(info)
	_ok(kc.is_playing(), "the replay starts from a recorded clip")
	_ok(kc._ghosts.size() >= 1, "ghosts are built (%d)" % kc._ghosts.size())
	_ok(kc._cam != null, "the killer's camera exists")
	_ok(kc._overlay != null, "the overlay is built")
	_ok(kc._title != null, "the title label is there")
	# Play a second of it on explicit deltas: this is where the pose blend, the weapon model and the
	# tracers run, and where a broken member access would show up.
	var seen_move := false
	var start_pos := Vector3.ZERO
	for i in 90:
		kc._process(1.0 / 60.0)
		var g: Variant = kc._ghosts.get(me.peer_id)
		if g != null:
			var at: Vector3 = (g.root as Node3D).global_position
			if start_pos == Vector3.ZERO:
				start_pos = at
			elif at.distance_to(start_pos) > 0.01:
				seen_move = true
		if not kc.is_playing():
			break
	_ok(kc._real_t > 0.4, "the replay clock ran (%.2f s)" % kc._real_t)
	_ok(seen_move, "the killer's ghost moved between snapshots")
	_ok(kc._cam.current, "the replay camera is the one being rendered")
	var ghost_root: Node3D = (kc._ghosts.values()[0] as Dictionary).root
	kc._end_playback()
	_ok(not kc.is_playing(), "the replay ends")
	_ok(kc._ghosts.is_empty(), "the ghosts are freed")
	_ok(kc._overlay == null, "the overlay is freed")
	_ok(not is_instance_valid(ghost_root) or ghost_root.is_queued_for_deletion(), "the ghost nodes go away")
	print("KILLCAM PLAY CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
