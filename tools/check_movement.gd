extends Node
## #80/#81 headless: wallrun, wall jump, wall to wall, dive (slide jump + air), roll keeps speed,
## and the movement tricks in Style.detect. Builds a test box high above the map.
##   godot --headless res://tools/check_movement.tscn      → "MOVEMENT CHECK OK"
##   online (server scores WALL TO WALL from the synced move_fx/walljumps):
##     godot --headless -- --server --port 7799 --map quay --mode ffa --bots 0
##     godot --headless res://tools/check_movement.tscn -- --net
var fails := 0
var net := false
var me: Player
const BASE := Vector3(0, 300, 0)


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _release_all() -> void:
	for a in ["sprint", "move_forward", "crouch", "jump", "move_left", "move_right"]:
		Input.action_release(a)


func _place(pos: Vector3, vel: Vector3, yaw: float) -> void:
	_release_all()
	me.global_position = pos
	me.velocity = vel
	me.rotation.y = yaw
	me._yaw = yaw
	me._reset_style_track()
	me._sliding = false
	await _frames(1)


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	net = OS.get_cmdline_user_args().has("--net")
	if net:
		menu.set_host_ip("127.0.0.1")
		menu.set_host_port(7799)
		menu.connect_pressed.emit()
	else:
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
	_ok(me != null and (Game._round_active or net), "round running")
	if me == null:
		_done()
		return
	me._spawn_protect = 999.0
	# Floor far below, two parallel walls 8 m apart along Z (faces at x = +2.5 and x = -5.5).
	_box(BASE + Vector3(0, -60, 0), Vector3(400, 1, 400))
	_box(BASE + Vector3(3, 0, 0), Vector3(1, 40, 200))
	_box(BASE + Vector3(-6, 0, 0), Vector3(1, 40, 200))
	# Flat test floor for dive/roll, off to the side.
	_box(BASE + Vector3(100, -0.5, 0), Vector3(60, 1, 200))
	await _frames(2)
	await _wallrun()
	await _walljump()
	await _dive()
	_style_unit()
	_done()


## Facing +Z (yaw PI), moving along the +X wall at sprint speed, sprint + forward held.
func _wallrun() -> void:
	await _place(BASE + Vector3(1.9, 0, -60), Vector3(0, 1.0, 11.4), PI)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var started := -1
	var ended := -1
	var y0 := 0.0
	var min_vy := 0.0
	var speed_mid := 0.0
	for i in 150:
		await _frames(1)
		if me.is_wallrunning() and started < 0:
			started = i
			y0 = me.global_position.y
		if started >= 0 and me.is_wallrunning():
			min_vy = minf(min_vy, me.velocity.y)
			if i - started == 30:
				speed_mid = Vector2(me.velocity.x, me.velocity.z).length()
		if started >= 0 and ended < 0 and not me.is_wallrunning():
			ended = i
	var dur := float(ended - started) / float(Engine.physics_ticks_per_second)
	print("  wallrun start f%d end f%d (%.2f s), speed %.1f, min vy %.2f" % [started, ended, dur, speed_mid, min_vy])
	_ok(started >= 0 and started < 10, "wallrun starts on touching the wall")
	_ok(ended > started and dur <= Player.WALLRUN_TIME + 0.1 and dur >= Player.WALLRUN_TIME * 0.8, "wallrun lasts about WALLRUN_TIME")
	_ok(min_vy >= -Player.WALLRUN_SINK_END - 0.01, "sinks slowly (not free fall)")
	_ok(speed_mid >= 10.0, "keeps speed along the wall")
	_ok(me.move_fx == Player.MOVE_NONE or not me.is_wallrunning(), "move_fx follows")
	# Same wall again, still airborne: no second run.
	var again := false
	for i in 40:
		await _frames(1)
		again = again or me.is_wallrunning()
	_ok(not again, "same wall cannot be run again before the ground")
	_release_all()


func _walljump() -> void:
	await _place(BASE + Vector3(1.9, 0, -60), Vector3(0, 1.0, 11.4), PI)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(15)
	_ok(me.is_wallrunning(), "wallrun before the wall jump")
	var jumps0 := me.walljumps
	var pid := multiplayer.get_unique_id()
	var style0 := int(Game.scores[pid].get("style", 0))
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	print("  after wall jump vel %s seen_t %.2f clock %.2f seen %d in_air %s" % [str(me.velocity), me._walljump_seen_t, me._style_clock, me._walljumps_seen, me._style_in_air])
	_ok(me.walljumps == jumps0 + 1, "wall jump counted (synced walljumps)")
	_ok(me.velocity.x < -4.0 and me.velocity.y > 3.0, "wall jump pushes away and up")
	if not net:
		_ok(me.style_walljump(), "server sees the wall jump (style_walljump)")
	var second := false
	for i in 120:
		await _frames(1)
		if me.is_wallrunning():
			second = true
			break
	_ok(second, "second wallrun on the other wall")
	await _frames(30 if net else 3)
	var style1 := int(Game.scores[pid].get("style", 0))
	_ok(style1 - style0 == int(Style.POINTS[Style.WALL_TO_WALL]), "WALL TO WALL scored (%d)" % (style1 - style0))
	_release_all()


func _dive() -> void:
	var fl := BASE + Vector3(100, 0.05, -80)
	await _place(fl, Vector3(0, 0, 11.4), PI)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_press("crouch")
	await _frames(3)
	_ok(me.is_sliding(), "sprint + crouch on the ground is still the slide")
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	_ok(me.is_diving(), "jump out of the slide dives")
	var sp_dive := Vector2(me.velocity.x, me.velocity.z).length()
	_ok(sp_dive > Player.SPRINT_SPEED, "dive is faster than sprint (%.1f)" % sp_dive)
	var rolled := false
	var sp_land := 0.0
	for i in 120:
		await _frames(1)
		if me.is_rolling():
			rolled = true
			sp_land = Vector2(me.velocity.x, me.velocity.z).length()
			break
	_ok(rolled, "landing from the dive rolls")
	if not net:
		_ok(me.style_dive() or me.style_roll(), "server saw the dive/roll")
	await _frames(int(Player.ROLL_TIME * Engine.physics_ticks_per_second) + 2)
	var sp_after := Vector2(me.velocity.x, me.velocity.z).length()
	print("  dive %.1f, landing %.1f, after roll %.1f m/s" % [sp_dive, sp_land, sp_after])
	_ok(sp_after >= sp_land * 0.85, "the roll keeps momentum")
	# Air dive: jump while sprinting, crouch in the air.
	Input.action_release("crouch")
	await _place(fl + Vector3(0, 0, 40), Vector3(0, 0, 11.4), PI)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(10)
	Input.action_press("jump")
	await _frames(4)
	Input.action_release("jump")
	Input.action_press("crouch")
	await _frames(2)
	_ok(me.is_diving(), "sprint + crouch in the air dives")
	_release_all()
	await _frames(60)


func _style_unit() -> void:
	var t := Style.detect({"weapon": &"rifle", "wallrun": true, "shooter_air": 1.0})
	_ok(t.has(Style.WALLRUN) and not t.has(Style.AIRSHOT), "WALLRUN KILL (replaces own AIRSHOT)")
	t = Style.detect({"weapon": &"smg", "walljump": true, "wallrun": true})
	_ok(t.has(Style.WALLJUMP) and not t.has(Style.WALLRUN), "WALL JUMP KILL wins over WALLRUN")
	t = Style.detect({"weapon": &"shotgun", "dive": true, "roll": true})
	_ok(t.has(Style.DIVE) and not t.has(Style.ROLL), "DIVE KILL")
	t = Style.detect({"weapon": &"melee", "roll": true})
	_ok(t.has(Style.ROLL), "ROLL KILL with the knife")
	t = Style.detect({"weapon": &"grenade", "dive": true})
	_ok(t.is_empty(), "grenades get no movement tricks")


func _done() -> void:
	_release_all()
	print("MOVEMENT CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)
