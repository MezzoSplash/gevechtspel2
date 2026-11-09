extends Node
## #249 headless: a landing roll cannot be cut short by a jump, and a jump out of the roll drops the
## dive speed to sprint. Drives a real pawn through slide -> dive -> roll on a flat test floor and
## presses jump on the landing frame (the dive -> space chain that started the issue), then checks the
## roll that is rolled out still pays its carry, and that a plain sprint jump is untouched.
##   godot --headless res://tools/check_dive_jump.tscn   → "DIVE JUMP CHECK OK"
var fails := 0
var me: Player
var failed: Array[String] = []
const BASE := Vector3(0, 300, 0)
const FLOOR := BASE + Vector3(100, 0.05, -80)
## Horizontal speed on the frame the landing roll started, filled by _into_roll.
var roll_speed := 0.0


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
	me._roll_t = 0.0
	me._carry_t = 0.0
	me._diving = false
	me._dive_cd = 0.0
	await _frames(1)


## Slide (sprint + crouch), jump out of it into a dive, then wait for the landing roll.
## `dive_speed` (optional) lifts the horizontal speed during the dive, because a slide alone tops out
## at sprint and a landing roll has to start faster than sprint for the jump cap to mean anything.
## Returns the frame after the dive jump on which the roll appeared, or -1.
func _into_roll(dive_speed := 0.0) -> int:
	await _place(FLOOR, Vector3(0, 0, Player.SPRINT_SPEED), PI)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_press("crouch")
	await _frames(3)
	_ok(me.is_sliding(), "sprint + crouch on the ground is still the slide")
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	_ok(me.is_diving(), "jump out of the slide still dives (unchanged)")
	if dive_speed > 0.0:
		var h := Vector3(me.velocity.x, 0.0, me.velocity.z)
		if h.length() > 0.01:
			h = h.normalized() * minf(dive_speed, Player.DIVE_MAX)
			me.velocity.x = h.x
			me.velocity.z = h.z
	var roll := -1
	for i in 120:
		await _frames(1)
		if me.is_rolling():
			roll = i
			roll_speed = Vector2(me.velocity.x, me.velocity.z).length()
			break
	return roll


## The reported chain: dive, land, tap space. The roll must survive ROLL_JUMP_LOCK, the press must be
## held (not eaten) and the jump that finally fires must not carry the dive speed.
func _lock() -> void:
	# Pin the number from #249: the timing assertions below scale with the constant, so a constant
	# that quietly moves to 0 (or 0.05) would otherwise make them pass while the bug is back.
	_ok(is_equal_approx(Player.ROLL_JUMP_LOCK, 0.3), "ROLL_JUMP_LOCK is 0.3 s (%.2f)" % Player.ROLL_JUMP_LOCK)
	var roll := await _into_roll(Player.DIVE_MAX)
	_ok(roll >= 0, "landing from the dive rolls")
	if roll < 0:
		return
	var ticks := float(Engine.physics_ticks_per_second)
	var sp_roll := roll_speed
	Input.action_press("jump")
	var jump_frame := -1
	var sp_jump := 0.0
	var rolled_frames := 0
	var fx_is_roll := true
	for i in 90:
		await _frames(1)
		if i == 1:
			Input.action_release("jump")
		if me.is_rolling():
			rolled_frames += 1
			fx_is_roll = fx_is_roll and me.move_fx == Player.MOVE_ROLL
		if jump_frame < 0 and me.velocity.y > 1.0:
			jump_frame = i
			sp_jump = Vector2(me.velocity.x, me.velocity.z).length()
			break
	var lock_s := float(jump_frame) / ticks
	print("  roll at %.1f m/s, jumped at %.2f s (lock %.2f s), speed after %.1f m/s" % [sp_roll, lock_s, Player.ROLL_JUMP_LOCK, sp_jump])
	_ok(jump_frame > 0, "the kept press does jump once the lock is over")
	_ok(lock_s >= Player.ROLL_JUMP_LOCK - 0.05, "no jump inside ROLL_JUMP_LOCK")
	_ok(lock_s <= Player.ROLL_JUMP_LOCK + 0.15, "the buffered press is kept, not eaten")
	_ok(rolled_frames >= int(Player.ROLL_JUMP_LOCK * ticks) - 1, "the roll is visible for at least ROLL_JUMP_LOCK (%d frames)" % rolled_frames)
	_ok(fx_is_roll, "move_fx stays MOVE_ROLL through the lock (remote pawns see the roll too)")
	_ok(sp_roll > Player.SPRINT_SPEED + 1.0, "the dive lands fast enough for the cap to matter (%.1f m/s)" % sp_roll)
	_ok(sp_jump <= Player.SPRINT_SPEED + 0.1, "a roll jump drops the dive speed to sprint")
	_release_all()
	await _frames(90)


## Rolling it out is the reward: the carry still starts and the momentum survives.
func _roll_out() -> void:
	var roll := await _into_roll(Player.DIVE_MAX)
	if roll < 0:
		_ok(false, "second dive rolls")
		return
	var sp_land := roll_speed
	Input.action_release("crouch")
	var carried := false
	for i in 120:
		await _frames(1)
		if not me.is_rolling() and me._carry_t > 0.0:
			carried = true
			break
	var sp_after := Vector2(me.velocity.x, me.velocity.z).length()
	print("  roll out: landing %.1f, carry left %.2f s, after %.1f m/s" % [sp_land, me._carry_t, sp_after])
	_ok(carried, "rolling it out still starts ROLL_CARRY")
	# ROLL_FRICTION is a slow bleed, not a cut: a fast dive roll still ends at or above sprint, and
	# ROLL_CARRY takes over from there. (The old 0.85-of-landing threshold fails for a 13 m/s roll.)
	_ok(sp_after >= Player.SPRINT_SPEED - 0.6, "and keeps the momentum (%.1f m/s after a %.1f m/s roll)" % [sp_after, sp_land])
	_release_all()
	await _frames(90)


## The cap is roll-only: a plain sprint jump keeps its sprint speed.
func _sprint_jump() -> void:
	await _place(FLOOR, Vector3(0, 0, Player.SPRINT_SPEED), PI)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(20)
	_ok(not me.is_rolling(), "no roll on a plain sprint")
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	var vy := me.velocity.y
	var sp := Vector2(me.velocity.x, me.velocity.z).length()
	print("  sprint jump: vy %.1f, speed %.1f m/s" % [vy, sp])
	_ok(vy > 5.0, "a plain sprint jump still jumps")
	_ok(sp >= Player.SPRINT_SPEED - 0.2, "and keeps its sprint speed (the cap is roll-only)")
	_release_all()


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
	# The class picker holds Game.pause_open, and the pawn does not move behind a menu.
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	await _frames(2)
	_box(FLOOR + Vector3(0, -0.55, 0), Vector3(60, 1, 200))
	await _frames(2)
	await _lock()
	await _roll_out()
	await _sprint_jump()
	_done()


func _done() -> void:
	_release_all()
	print("DIVE JUMP CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in failed:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails else 0)
