extends Node
## Parity probe for movement refactors (not a check; run_checks skips probe_*): a fixed input script on
## the local pawn - sprint, jumps, a slide into a dive, air strafing through a turn, a wallrun - one line
## per physics tick with position, velocity, slide and wallrun, so two builds can be diffed:
##   godot --headless --fixed-fps 60 res://tools/probe_move_trace.tscn -- /tmp/a.txt   (on each build)
##   cmp /tmp/a.txt /tmp/b.txt
## The trace is deterministic run to run at --fixed-fps 60. #316 used it: MoveTick left it byte-identical.
var me: Player
var out: PackedStringArray = []
const BASE := Vector3(0, 300, 0)


func _box(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	s.shape = sh
	b.add_child(s)
	get_tree().root.add_child(b)
	b.global_position = pos


func _ready() -> void:
	seed(1)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_FFA)
	Game.bot_count = 0
	for b in menu._bot_boxes:
		b.value = 0
	menu.play_local_pressed.emit()
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not Game.play_locked() and Game._round_active:
			break
	me._spawn_protect = 999.0
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	_box(BASE + Vector3(0, -0.5, 0), Vector3(200, 1, 400)) # floor
	_box(BASE + Vector3(-6, 3, -60), Vector3(1, 12, 60)) # a wall on the left further on
	await get_tree().physics_frame
	me.global_position = BASE + Vector3(0, 1.2, 0)
	me.velocity = Vector3.ZERO
	me.rotation.y = 0.0
	me._yaw = 0.0
	await get_tree().physics_frame
	# [tick, press, release]
	var script := [
		[0, ["move_forward", "sprint"], []],
		[40, ["jump"], []], [42, [], ["jump"]],
		[125, ["crouch"], []], [135, ["jump"], []], [137, [], ["jump", "crouch"]],
		[150, ["move_left"], []], [175, [], ["move_left"]],
		[200, ["jump"], []], [202, [], ["jump"]], [205, ["move_right"], []], [230, [], ["move_right"]],
		[260, ["crouch"], []], [300, [], ["crouch", "sprint"]],
		[320, ["jump"], []], [322, [], ["jump"]],
		[380, [], ["move_forward"]],
	]
	var k := 0
	for t in 420:
		while k < script.size() and int(script[k][0]) == t:
			for a in script[k][1]:
				Input.action_press(a)
			for a in script[k][2]:
				Input.action_release(a)
			k += 1
		if t >= 140 and t < 260:
			me.rotation.y += 0.004 # a gentle turn, so air strafing bends the path
			me._yaw = me.rotation.y
		await get_tree().physics_frame
		var p := me.global_position - BASE
		var v := me.velocity
		out.append("%d %.4f %.4f %.4f %.4f %.4f %.4f %d %d" % [t, p.x, p.y, p.z, v.x, v.y, v.z, int(me._sliding), int(me._wallrunning)])
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()
