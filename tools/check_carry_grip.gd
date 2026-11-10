extends Node
## #251 headless: a carry steers like grip instead of drifting. A real pawn is put into carry at
## 15 m/s and holds one direction; the velocity has to turn toward it (> 60 deg in half a second) with
## the speed kept (>= 13 m/s), which is exactly what the old accelerate-only carry could not do.
## Counter-steering brakes instead of turning, no keys keeps the release friction, the carry ends on a
## slope (no frame loses more than 1 m/s) and the landing roll steers too, only slower.
##   godot --headless res://tools/check_carry_grip.tscn   → "CARRY GRIP CHECK OK"
var fails := 0
var me: Player
var failed: Array[String] = []
const BASE := Vector3(0, 300, 0)
const FLOOR := BASE + Vector3(100, 0.05, -80)
const SPEED := 15.0 # inside the carry band (CARRY_ENTER_SPEED 12 .. CARRY_MAX 18)


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1
		failed.append(msg)


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
	for a in ["sprint", "move_forward", "move_back", "crouch", "jump", "move_left", "move_right"]:
		Input.action_release(a)


func _hspeed() -> float:
	return Vector2(me.velocity.x, me.velocity.z).length()


## Degrees the horizontal velocity has turned away from +Z, the direction it is placed in.
func _turned() -> float:
	var h := Vector3(me.velocity.x, 0.0, me.velocity.z)
	if h.length_squared() < 0.01:
		return 0.0
	return rad_to_deg(absf(Vector3(0, 0, 1).signed_angle_to(h, Vector3.UP)))


## Facing +Z (yaw PI), moving +Z at SPEED, on the floor, with a full carry timer.
func _into_carry() -> void:
	_release_all()
	me.global_position = FLOOR
	me.velocity = Vector3(0, 0, SPEED)
	me.rotation.y = PI
	me._yaw = PI
	me._reset_style_track()
	me._sliding = false
	me._roll_t = 0.0
	me._carry_t = 0.0
	me._diving = false
	me._dive_cd = 0.0
	await _frames(1)
	me.velocity = Vector3(0, 0, SPEED)
	me._carry_t = Player.CARRY_TIME


## The reported feel: at carry speed a held key has to bend the path, not leave you drifting past it.
func _steer() -> void:
	await _into_carry()
	Input.action_press("move_right")
	await _frames(30)
	var turned := _turned()
	var sp := _hspeed()
	Input.action_release("move_right")
	print("  steer: turned %.0f deg, speed %.1f m/s" % [turned, sp])
	_ok(turned > 60.0, "holding a direction turns the carry (%.0f deg in 0.5 s)" % turned)
	_ok(sp >= 13.0, "and keeps the speed while turning (%.1f from %.1f m/s)" % [sp, SPEED])
	await _frames(60)


## Pressing the opposite way is a brake, not a 180: the carry scrubs the speed.
func _counter() -> void:
	await _into_carry()
	Input.action_press("move_back")
	await _frames(30)
	var sp := _hspeed()
	var turned := _turned()
	Input.action_release("move_back")
	print("  counter: speed %.1f m/s after 0.5 s, turned %.0f deg" % [sp, turned])
	_ok(sp < 9.0, "counter-steering brakes instead of turning (%.1f m/s)" % sp)
	await _frames(60)


## No keys: the release friction still parks you, and nothing turns on its own.
func _release() -> void:
	await _into_carry()
	await _frames(30)
	var sp := _hspeed()
	var turned := _turned()
	print("  no keys: speed %.1f m/s after 0.5 s, turned %.0f deg" % [sp, turned])
	_ok(sp < 4.0, "no keys still brakes on CARRY_RELEASE_FRICTION (%.1f m/s)" % sp)
	_ok(turned < 5.0, "and does not steer by itself (%.0f deg)" % turned)
	await _frames(60)


## The carry used to end on a hard cut (ground friction 10 hits in one frame, ~2 m/s gone at carry
## speed). The last CARRY_FADE seconds ramp it in, so no single frame may lose 1 m/s or more.
## Running a carry out has to hand over to normal ground movement at sprint, not at a stop (playtest on
## #251): the fade ramps the friction up and accelerate refills toward wish speed in the same tick.
func _fade() -> void:
	_ok(Player.CARRY_FADE < Player.CARRY_TIME, "CARRY_FADE (%.2f s) fits inside CARRY_TIME (%.1f s)" % [Player.CARRY_FADE, Player.CARRY_TIME])
	await _into_carry()
	Input.action_press("sprint")
	Input.action_press("move_forward") # straight ahead: no turn, so only the friction shows
	var prev := _hspeed()
	var max_drop := 0.0
	var sp_end := -1.0
	var frames := 0
	for i in 300:
		await _frames(1)
		frames += 1
		var sp := _hspeed()
		max_drop = maxf(max_drop, prev - sp)
		prev = sp
		if sp_end < 0.0 and me._carry_t <= 0.0:
			sp_end = sp
		if sp_end >= 0.0 and i > int(Player.CARRY_TIME * Engine.physics_ticks_per_second) + 30:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	print("  fade: carry over after %d frames, %.1f m/s at the end, worst frame -%.2f m/s" % [frames, sp_end, max_drop])
	_ok(sp_end >= 0.0, "the carry still ends on its own without a jump")
	_ok(sp_end >= Player.SPRINT_SPEED - 1.0, "and hands over at sprint, not at a stop (%.1f m/s)" % sp_end)
	_ok(max_drop < 1.0, "no frame drops 1 m/s or more (worst %.2f m/s)" % max_drop)
	await _frames(60)


## The roll steers through the same helper, only at ROLL_TURN_RATE: a third of a carry's turn in the
## same time, so it cannot quietly become a carry.
func _roll() -> void:
	_release_all()
	me.global_position = FLOOR
	me.velocity = Vector3(0, 0, SPEED)
	me.rotation.y = PI
	me._yaw = PI
	me._carry_t = 0.0
	me._sliding = false
	me._diving = false
	await _frames(1)
	me.velocity = Vector3(0, 0, SPEED)
	me._roll_t = Player.ROLL_TIME
	Input.action_press("move_right")
	await _frames(12)
	var turned := _turned()
	var sp := _hspeed()
	Input.action_release("move_right")
	me._roll_t = 0.0
	print("  roll: turned %.0f deg in 0.2 s, speed %.1f m/s" % [turned, sp])
	_ok(turned > 25.0, "a landing roll can be steered too (%.0f deg in 0.2 s)" % turned)
	_ok(turned < 60.0, "but slower than a carry (%.0f deg, carry would be ~80)" % turned)
	_ok(sp >= Player.SPRINT_SPEED, "the roll keeps its speed while steering (%.1f m/s)" % sp)
	await _frames(60)


func _ready() -> void:
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
	_ok(me != null and Game._round_active, "round running")
	if me == null:
		_done()
		return
	me._spawn_protect = 999.0
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	await _frames(2)
	_box(FLOOR + Vector3(0, -0.55, 0), Vector3(60, 1, 200))
	await _frames(2)
	await _steer()
	await _counter()
	await _release()
	await _fade()
	await _roll()
	_done()


func _done() -> void:
	_release_all()
	print("CARRY GRIP CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in failed:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails else 0)
