extends Node
## NOT a CI check (run_checks.sh only runs check_*): a probe to watch a bot wallrun in a real match.
## Puts one Hard bot on a flat test floor 3 m beside a 60 m wall, with the human pawn far down the line so the bot
## runs the wall's way, and prints three attempts: did a wallrun start, how long, did it jump off, how fast it was.
## The wall finder itself is covered by check_bot_wall; this is for the feel (entry angle, run length, wall jump).
##   godot --headless res://tools/probe_bot_wall.tscn      (or ./run.sh and read the console)
const BASE := Vector3(0, 300, 0)
const RUNS := 3
const RUN_TIME := 7.0
var me: Player
var bot: Player


func _box(center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	s.shape = sh
	b.add_child(s)
	get_tree().root.add_child(b)
	b.global_position = center


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.bot_difficulty = Game.BOT_HARD
	Game.last_bots = 1
	Game.bot_count = 1
	menu.set_match_choice(&"quay", Game.MODE_FFA)
	for b in menu._bot_boxes:
		b.value = 1
	menu.play_local_pressed.emit()
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		bot = null
		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Player
			if p and p.is_bot:
				bot = p
		if me and bot and not Game.play_locked() and Game._round_active:
			break
	if me == null or bot == null:
		print("PROBE: no human pawn or no bot (me=%s bot=%s)" % [me, bot])
		get_tree().quit(1)
		return
	me._spawn_protect = 999.0
	bot._spawn_protect = 999.0
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	_box(BASE + Vector3(30, -0.5, 0), Vector3(200, 1, 60)) # floor
	_box(BASE + Vector3(30, 2.0, 3.5), Vector3(60, 4, 1)) # wall: face at z = 3, x from 0 to 60
	await get_tree().physics_frame
	await get_tree().physics_frame
	for run in RUNS:
		await _attempt(run + 1)
	get_tree().quit(0)


func _attempt(run: int) -> void:
	me.global_position = BASE + Vector3(80, 0.1, 0.0) # far down the line: out of fight range
	me.velocity = Vector3.ZERO
	bot.global_position = BASE + Vector3(-20, 0.1, 0.5)
	bot.velocity = Vector3.ZERO
	var brain = bot._bot_brain
	brain._trick_cd = 0.0
	brain._end_wall_trick()
	brain._trick_cd = 0.0
	var was_running := false
	var run_start := 0.0
	var runs := 0
	var longest := 0.0
	var jumps_before: int = bot.walljumps
	var speed_in := 0.0
	var t := 0.0
	while t < RUN_TIME:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if bot._wallrunning and not was_running:
			runs += 1
			run_start = t
			speed_in = Vector2(bot.velocity.x, bot.velocity.z).length()
		if not bot._wallrunning and was_running:
			longest = maxf(longest, t - run_start)
		was_running = bot._wallrunning
	print("PROBE run %d: wallruns=%d longest=%.2fs entry_speed=%.1f m/s walljumps=%d  end pos x=%.1f y=%.1f (floor y=%.0f)" % [
		run, runs, longest, speed_in, bot.walljumps - jumps_before, bot.global_position.x - BASE.x,
		bot.global_position.y, BASE.y])
