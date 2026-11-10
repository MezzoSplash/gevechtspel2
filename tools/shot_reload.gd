extends Node
## #252: renders the four reload styles so a human can judge them. Not part of run_checks.sh (it needs
## a real screen). One image per style per progress point, from the player's own camera.
##   xvfb-run -a godot --path . res://tools/shot_reload.tscn -- --out /tmp
const POINTS: Array[float] = [0.3, 0.55, 0.85]
const GUNS := {
	"mag": "rifle",
	"shells": "shotgun",
	"cylinder": "revolver",
	"bolt": "sniper",
}


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
	Game.last_bots = 0
	Game.bot_count = 0
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	# Wait for the round to actually run: the round-start freeze respawns the pawn and cancels a reload
	# that is already playing, which used to make the last styles shoot an empty screen.
	var me: Player = null
	for i in 900:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and not Game.play_locked() and Game._round_active:
			break
	if me == null:
		print("SHOT RELOAD: no local pawn")
		get_tree().quit(1)
		return
	# The round start respawns the pawn and can reopen the class picker, whose camera would be the one
	# rendering: close it again and wait until our own camera is the active one.
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	for i in 200:
		var p := Game.player_for_peer(multiplayer.get_unique_id())
		if p != null and p.weapon != null and p.camera.current:
			me = p
			break
		if p != null and p.weapon != null and main.class_select != null and main.class_select.is_open():
			main.class_select.close_silently()
			Game.pause_open = false
		await get_tree().physics_frame
	if not me.camera.current:
		print("SHOT RELOAD: the pawn camera is not the active one")
		get_tree().quit(1)
		return
	me._spawn_protect = 999.0
	main.get_node("CanvasLayer").visible = false
	# Open floor in the plaza: a spawn can put the lens against a wall, which hides the very thing these
	# shots are for.
	me.velocity = Vector3.ZERO
	# No sway: a slow renderer (xvfb) gives the sway spring big frame times, and a kicked spring swings
	# the gun metres out of frame — which is not what these shots are about.
	Game.view_sway = 0
	# Hide the arena: the gun then sits on a plain background instead of on whatever wall happens to be
	# beside the spawn, which is all these shots are about. The map's own light and environment go with
	# it, so the gun gets its own.
	main.world.visible = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.19, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.8)
	env.ambient_light_energy = 1.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	sun.light_energy = 2.0
	add_child(sun)
	# Let the viewmodel sway spring settle: the respawn kicks it, and a kicked gun swings out of frame.
	for i in 240:
		await get_tree().physics_frame
	var w := me.weapon
	for style in GUNS:
		w.set_slots([GUNS[style]])
		w.ammo = maxi(w.def.mag_size - 4, 0)
		await get_tree().physics_frame
		w._start_reload()
		var done := 0
		for i in 600:
			await get_tree().physics_frame
			var t := w.reload_anim()
			if done < POINTS.size() and t >= POINTS[done]:
				_grab("%s/reload_%s_%02d.png" % [out, style, int(POINTS[done] * 100.0)])
				done += 1
			if done >= POINTS.size():
				break
		for i in 200:
			await get_tree().physics_frame
			if w.reload_anim() <= 0.0:
				break
		match style:
			"mag":
				w.set_slots(["lmg"])
				w.ammo = 40
				await get_tree().physics_frame
				w._start_reload()
				for i in 600:
					await get_tree().physics_frame
					if w.reload_anim() >= 0.32:
						_grab("%s/reload_lmg_cover.png" % out)
						break
				w._cancel_reload()
	print("SHOT RELOAD: done")
	get_tree().quit()


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())
