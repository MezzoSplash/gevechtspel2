extends Node
## Renders the crouch from outside so a human can judge it: the local pawn, pressed into a real crouch
## (input, so the stance blend and head height are the game's own), shot from the side and from the
## front three-quarter while standing, halfway down, crouched, and crouch-walking. Not in run_checks.sh
## (it needs a real screen).
##   godot --path . res://tools/shot_crouch.tscn -- --out /tmp
var out := "/tmp"
var me: Player
var cam: Camera3D


func _ready() -> void:
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
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and Game._round_active and not Game.play_locked():
			break
	if me == null:
		print("SHOT: no local pawn")
		get_tree().quit(1)
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	me._spawn_protect = 999.0
	me.body_mesh.visible = true
	var hud := main.get_node_or_null("CanvasLayer")
	if hud:
		hud.visible = false
	cam = Camera3D.new()
	cam.fov = 40.0
	get_tree().root.add_child(cam)
	cam.current = true
	await _settle(0.6)
	await _shots("stand")
	Input.action_press("crouch")
	await _settle(0.06)
	await _shots("half")
	await _settle(0.8)
	await _shots("crouch")
	Input.action_press("move_forward")
	await _settle(0.5)
	for i in 3:
		await _shots("crouchwalk%d" % i)
		await _settle(0.13)
	Input.action_release("move_forward")
	Input.action_release("crouch")
	await _settle(0.8)
	await _shots("standup")
	print("SHOT crouch: done -> %s/crouch-*.png" % out)
	get_tree().quit(0)


func _settle(t: float) -> void:
	var left := t
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


## Two angles, aimed at the pawn's hips, framed on a standing body so the crouch shows as the drop.
func _shots(tag: String) -> void:
	var b := me.global_transform.basis
	var at := me.global_position + Vector3.UP * 0.85
	var views := {
		"side": at + b.x * 3.4 + Vector3.UP * 0.2,
		"front": at - b.z * 2.6 + b.x * 1.6 + Vector3.UP * 0.4,
	}
	for v in views:
		var p: Vector3 = views[v]
		cam.global_position = p
		cam.look_at(at, Vector3.UP)
		# The pose blends on _process; the camera move needs two frames before the image is drawn.
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/crouch-%s-%s.png" % [out, tag, v])
