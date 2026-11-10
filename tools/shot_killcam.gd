extends Node
## #258: renders the final killcam so a human can judge the cut and the VHS fast-forward. Not part of
## run_checks.sh (it needs a real screen).
##   xvfb-run -a godot --path . res://tools/shot_killcam.tscn -- --out /tmp
const POINTS: Array[float] = [0.8, 2.0, 3.4, 5.2]


func _ready() -> void:
	var out := "/tmp"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 5
	Game.bot_count = 5
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and not Game.play_locked() and Game._round_active:
			break
	if me == null:
		print("SHOT KILLCAM: no round")
		get_tree().quit(1)
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	# Let the rolling buffer fill: the director can reach LOOKBACK (9 s) back.
	for i in 900:
		await get_tree().physics_frame
		if Game.killcam._clock > 10.0:
			break
	# The last death in the buffer, played as the final killcam with a combo title.
	var victim := 0
	var events: Array = Game.killcam._events
	for i in range(events.size() - 1, -1, -1):
		if str(events[i][1]) == "death":
			victim = int(events[i][2])
			break
	var killer := me.peer_id
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p != null and p.peer_id != victim and p.peer_id != 0:
			killer = p.peer_id
			break
	var info := {
		"trick_id": 9999, # no stored trick clip: falls through to the victim's death (#88 path)
		"k": killer,
		"v": victim if victim != 0 else me.peer_id,
		"kt": 0,
		"vt": 1,
		"kn": "SHOT",
		"w": "rifle",
		"bank": 640,
		"pts": 300,
		"fallback": {"k": killer, "v": victim if victim != 0 else me.peer_id, "w": "rifle", "kn": "SHOT",
			"kt": 0, "vt": 1, "trick_id": 9999, "bank": 640, "pts": 300},
	}
	main.get_node("CanvasLayer").visible = false
	Game.killcam.play_final(info)
	if not Game.killcam.is_playing():
		print("SHOT KILLCAM: nothing to replay (kill fell out of the buffer)")
		get_tree().quit(1)
		return
	# Force a dull run over the whole clip so the VHS fast-forward is actually in the shots: a bot match
	# rarely has 9 s of the killer standing still.
	if args.has("--vhs"):
		Game.killcam._dull = [Vector2(Game.killcam._pt - 0.5, Game.killcam._t_end + 0.5)]
	var done := 0
	for i in 1200:
		await get_tree().process_frame
		if done < POINTS.size() and Game.killcam._real_t >= POINTS[done]:
			_grab("%s/killcam_%0.1f.png" % [out, POINTS[done]])
			done += 1
		if done >= POINTS.size() or not Game.killcam.is_playing():
			break
	print("SHOT KILLCAM: done")
	get_tree().quit()


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())
