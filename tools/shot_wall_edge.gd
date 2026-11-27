extends Node
## #320: renders the HUD with the wallrun light edge, left and right, so a human can judge it.
## Not part of run_checks.sh (it needs a real screen):
##   xvfb-run -a godot --path . res://tools/shot_wall_edge.tscn -- --out /tmp
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
		print("SHOT WALL EDGE: no round")
		get_tree().quit(1)
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	Game.speed_fx = true
	# The HUD is the thing being judged: no menu, no class select.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		print("SHOT WALL EDGE: no hud")
		get_tree().quit(1)
		return
	var overlay: HudOverlay = hud.overlay if hud.get("overlay") != null else null
	if overlay == null:
		print("SHOT WALL EDGE: no overlay")
		get_tree().quit(1)
		return
	# De beweging zet _wallrunning elke physics-tick opnieuw; voor een screenshot zetten we die uit zodat
	# de stand blijft staan.
	me.set_physics_process(false)
	# De normaal hangt aan de kijkrichting: de camera-rechts-as is de kant waar de muur NIET zit. De pop
	# staat niet op yaw 0, dus reken met de echte camera-basis in plaats van met wereld-X.
	var right := me.camera.global_transform.basis.x
	await _shot(me, overlay, right, "%s/wall_edge_left.png" % out)
	await _shot(me, overlay, -right, "%s/wall_edge_right.png" % out)
	print("SHOT WALL EDGE: done")
	get_tree().quit()


func _shot(me: Player, overlay: HudOverlay, normal: Vector3, path: String) -> void:
	me._wallrunning = true
	me._wall_n = normal
	me._wallrun_t = 0.25
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())
