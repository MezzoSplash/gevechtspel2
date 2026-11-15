extends Node
## #269. A Hard bot with an empty mag gets behind a crate before the reload finishes.
## Easy reloads in the open. Hard keeps the last round when the enemy is already within 6 m.
##   ./run.sh --headless res://tools/check_bot_cover.tscn   → "BOT COVER CHECK OK"
var fails := 0
var bot: Player
var enemy: Player
var brain: BotBrain
var crate: StaticBody3D
var baffle: StaticBody3D
var _phase := "boot"
var _ticks := 0
var _easy_hidden := false
var _hold_z := 0.0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _body(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.position = at
	add_child(body)
	return body


func _pawn(id: int, at: Vector3) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = id
	p.is_bot = true
	p.position = at
	p.name = "Bot%d" % id
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	p.grenades = 0
	return p


## Chest ray from the enemy. True only when the crate itself is what they would shoot.
func _behind_crate() -> bool:
	var space := bot.get_world_3d().direct_space_state
	var from := enemy.global_position + Vector3.UP * 0.9
	var to := bot.global_position + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = BotBrain.WORLD_MASK
	q.exclude = [bot.get_rid(), enemy.get_rid()]
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and hit.collider == crate


func _place(at: Vector3) -> void:
	bot.global_position = at
	bot.velocity = Vector3(0, -2, 0)
	brain._home = at
	brain._stuck_pos = at
	brain._target = null
	brain._retarget_t = 0.0
	brain._cover_live = false
	brain._unstick_left = 0.0


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	Game.bot_difficulty = Game.BOT_HARD
	# Floor top at y = 0. The crate sits just off the 45° line to the hide spot at 3 m,
	# so that ray is blocked and the straight run from the origin does not clip the box.
	# The short baffle on +X only closes Easy's strafe probe. It stays south of the run to
	# the hide spot, so it never counts as the cover the Hard bot is looking for.
	_body(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	crate = _body(Vector3(0.70, 1.30, 0.55), Vector3(1.90, 0.65, 0.725))
	baffle = _body(Vector3(0.3, 1.4, 0.8), Vector3(1.05, 0.7, 0.0))
	bot = _pawn(-1, Vector3(0, 0.2, 0))
	enemy = _pawn(-2, Vector3(0, 0.2, -9))
	enemy.set_physics_process(false)
	brain = BotBrain.new()
	brain.setup(bot, null)
	bot.weapon.ammo = 0
	_phase = "settle"


## Drop onto the floor, then run `next`. A teleport leaves is_on_floor() stale until a move.
func _settle(delta: float, next: String) -> void:
	bot.move_and_slide()
	_ticks += 1
	if not bot.is_on_floor() and _ticks <= 40:
		return
	_ticks = 0
	bot.velocity = Vector3.ZERO
	_phase = next
	if next == "hard":
		_ok(bot.is_on_floor(), "bot stood on the floor")
		_ok(not _behind_crate(), "starts in the open, beside the crate")
		var spot := brain._pick_cover(enemy)
		var dist := bot.global_position.distance_to(spot)
		_ok(not is_inf(spot.x) and dist <= BotBrain.COVER_R, "hide spot within 8 m (%.2f, %.2f)" % [spot.x, spot.z])
		bot.weapon.ammo = 0
		bot.weapon._reload_left = 0.0
		brain._cover_live = false


func _physics_process(delta: float) -> void:
	match _phase:
		"settle":
			_settle(delta, "hard")
		"hard":
			_tick_hard(delta)
		"easy_settle":
			_settle(delta, "easy")
		"easy":
			_tick_easy(delta)
		"hold_settle":
			_settle(delta, "hold")
		"hold":
			_tick_hold(delta)
		"flee_settle":
			bot.velocity = Vector3.ZERO
			bot.move_and_slide()
			_ticks += 1
			if _ticks >= 4:
				_ticks = 0
				brain._cover_live = false
				_phase = "flee"
		"flee":
			_tick_flee(delta)


func _tick_hard(delta: float) -> void:
	brain.physics_tick(delta)
	_ticks += 1
	if _behind_crate() and bot.weapon.is_reloading():
		_ok(bot.global_position.z > 1.0, "Hard is behind the crate (%.2f, %.2f) with the reload still running" % [
			bot.global_position.x, bot.global_position.z])
		_arm_easy()
		return
	var reload_done := bot.weapon.ammo > 0 and not bot.weapon.is_reloading() and _ticks > 5
	if _ticks > 80 or reload_done:
		_ok(false, "Hard never hid before the reload ended (pos %.2f, %.2f, tick %d, ammo %d)" % [
			bot.global_position.x, bot.global_position.z, _ticks, bot.weapon.ammo])
		_arm_easy()


func _arm_easy() -> void:
	Game.bot_difficulty = Game.BOT_EASY
	enemy.global_position = Vector3(0, enemy.global_position.y, -9)
	_place(Vector3(0, 0.2, 0))
	bot.weapon.ammo = 0
	bot.weapon._reload_left = 0.0
	# -X is away from the crate. Hold the commit so the probe does not flip them into it.
	brain._strafe_sign = -1.0
	brain._strafe_hold = 5.0
	brain._strafe_pause = 0.0
	brain._burst_left = 0
	brain._burst_pause = 0.0
	brain._acquire_left = 0.0
	brain._in_fight = false
	_easy_hidden = false
	_phase = "easy_settle"


func _tick_easy(delta: float) -> void:
	brain.physics_tick(delta)
	_ticks += 1
	if _behind_crate():
		_easy_hidden = true
	if _ticks < 45:
		return
	_ok(bot.weapon.is_reloading(), "Easy did start the reload")
	_ok(not _easy_hidden, "Easy is still in the open (pos %.2f, %.2f)" % [bot.global_position.x, bot.global_position.z])
	_arm_hold()


func _arm_hold() -> void:
	Game.bot_difficulty = Game.BOT_HARD
	enemy.global_position = Vector3(0, enemy.global_position.y, -4)
	_place(Vector3(0, 0.2, 0))
	bot.weapon.ammo = 1
	bot.weapon._reload_left = 0.0
	brain._acquire_left = 0.0
	brain._in_fight = false
	_phase = "hold_settle"


func _tick_hold(delta: float) -> void:
	if _ticks == 0:
		_hold_z = bot.global_position.z
	brain.physics_tick(delta)
	_ticks += 1
	if _ticks < 30:
		return
	_ok(bot.weapon.ammo == 1 and not bot.weapon.is_reloading(),
			"Hard keeps the last round inside 6 m (ammo %d)" % bot.weapon.ammo)
	_ok(bot.global_position.z < _hold_z - 0.35,
			"and closes instead (z %.2f -> %.2f)" % [_hold_z, bot.global_position.z])
	_arm_flee()


## Nothing to hide behind: sprint straight away, back toward the enemy, reload already started.
func _arm_flee() -> void:
	# Layer 0 takes a physics frame to drop out of the ray query. flee_settle burns those frames
	# before the brain picks, or it would still path to the crate that was just switched off.
	crate.collision_layer = 0
	baffle.collision_layer = 0
	Game.bot_difficulty = Game.BOT_HARD
	enemy.global_position = Vector3(0, enemy.global_position.y, -9)
	_place(Vector3(0, 0.2, 0))
	bot.weapon.ammo = 0
	bot.weapon._reload_left = 0.0
	brain._acquire_left = 0.0
	_phase = "flee_settle"


func _tick_flee(delta: float) -> void:
	brain.physics_tick(delta)
	_ticks += 1
	if _ticks < 40:
		return
	var away := bot.global_position.z > 1.2 and absf(bot.global_position.x) < 1.0
	# Godot's look_at points -Z at the travel direction, so basis.z.z is negative when running +Z.
	var back_to_enemy := bot.global_transform.basis.z.z < -0.5
	_ok(bot.weapon.is_reloading() and away, "with nowhere to hide, Hard runs straight away (%.2f, %.2f)" % [
		bot.global_position.x, bot.global_position.z])
	_ok(back_to_enemy, "and keeps its back to the enemy")
	_done()


func _done() -> void:
	set_physics_process(false)
	print("BOT COVER CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
