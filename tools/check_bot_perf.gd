extends Node
## #272. With 16 bots on the field, one physics tick of bot AI must not fire the same line-of-sight
## ray over and over. The same build is measured with the cache off (the old per-call behaviour) and
## with a few TTLs, and the staleness bound is asserted: an enemy that drops out of sight may stay
## visible for at most `los_ttl` ticks.
##   ./run.sh --headless res://tools/check_bot_perf.tscn   → "BOT PERF CHECK OK"
const BOTS := 16
const TICKS := 120
const FLOOR := Vector3(80, 1, 80)
var fails := 0
var fail_msgs: Array[String] = []
var pawns: Array[Player] = []
var brains: Array[BotBrain] = []
var _homes: Array[Vector3] = []
var _blink: StaticBody3D


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1
		fail_msgs.append(msg)


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


func _pawn(i: int, at: Vector3) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = -(i + 1)
	p.is_bot = true
	p.name = "Bot%d" % (i + 1)
	p.position = at
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	p.grenades = 0
	p.weapon.ammo = 30
	return p


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	Game.bot_difficulty = Game.BOT_HARD # omniscient: every bot picks a target and probes it
	_body(FLOOR, Vector3(0, -0.5, 0))
	# Four pillars so some probes end on a wall: both branches of `_can_see` (body ray, head ray) run.
	for c in [Vector3(6, 0, 6), Vector3(-6, 0, 6), Vector3(6, 0, -6), Vector3(-6, 0, -6)]:
		_body(Vector3(1.6, 3.0, 1.6), c + Vector3(0, 1.5, 0))
	# A single wall used by the staleness test, out of the way to start with.
	_blink = _body(Vector3(6, 3, 0.4), Vector3(0, 1.5, 40))
	for i in BOTS:
		var a := TAU * float(i) / float(BOTS)
		var at := Vector3(cos(a) * 9.0, 0.2, sin(a) * 9.0)
		pawns.append(_pawn(i, at))
		_homes.append(at)
	for p in pawns:
		var b := BotBrain.new()
		b.setup(p, null)
		brains.append(b)
	_settle_then_measure()


## Drop every pawn onto the floor first: a teleport leaves is_on_floor() stale until a move.
func _settle_then_measure() -> void:
	for i in 10:
		for p in pawns:
			p.move_and_slide()
		await get_tree().physics_frame
	await _measure()
	await _staleness()
	_done()


func _reset() -> void:
	for i in pawns.size():
		var p := pawns[i]
		p.global_position = _homes[i]
		p.velocity = Vector3.ZERO
		p.hp = Player.MAX_HP
		p.is_dead = false
		p.weapon.ammo = 30
		var b := brains[i]
		b.setup(p, null) # a fresh brain: no memory and no cached sight from the last run
		b.los_ttl = 1


## Ticks every brain once per frame and returns the LOS rays fired over the window.
func _window(cache: bool, ttl: int, ticks: int) -> int:
	_reset()
	for b in brains:
		b.los_cache = cache
		b.los_ttl = ttl
	BotBrain.los_rays = 0
	for i in ticks:
		# Nobody dies: the window has to measure the same crowd from start to end.
		for p in pawns:
			p.hp = Player.MAX_HP
			p.is_dead = false
		for b in brains:
			b.physics_tick(1.0 / 60.0)
		await get_tree().physics_frame
	return BotBrain.los_rays


const TTLS: Array[int] = [1, 2, 4, 6, 9]


func _measure() -> void:
	var cold := await _window(false, 1, TICKS)
	var per_bot_tick := float(BOTS * TICKS)
	print("  %d bots, %d ticks (rays per bot per tick):" % [BOTS, TICKS])
	print("    cache off     %6d  %.2f" % [cold, float(cold) / per_bot_tick])
	var measured := {}
	for t in TTLS:
		var warm := await _window(true, t, TICKS)
		measured[t] = warm
		print("    ttl %d ticks    %6d  %.2f  (-%.0f%%)" % [
			t, warm, float(warm) / per_bot_tick,
			100.0 * (1.0 - float(warm) / float(maxf(float(cold), 1.0)))])
	_ok(cold > 0, "the measurement actually fires rays (%d without cache)" % cold)
	# The shipped default is what has to earn its place, not a number tuned in the check.
	var shipped := BotBrain.new().los_ttl
	var warm: int = measured.get(shipped, cold)
	var cut := 1.0 - float(warm) / float(maxf(float(cold), 1.0))
	_ok(cut >= 0.5, "the shipped TTL (%d ticks) removes at least half the rays (%.0f%% fewer)" % [
		shipped, cut * 100.0])
	# 0.15 s at 60 Hz is the ceiling the issue names for a stale answer.
	_ok(shipped <= 9, "and stays under 0.15 s of staleness at 60 Hz (%d ticks)" % shipped)


## An enemy that drops out of sight stays visible for at most `los_ttl` ticks, never longer.
func _staleness() -> void:
	_reset()
	# Bot 0 looks at bot 1 from 6 m, both moved into the open NE corner.
	var a := pawns[0]
	var b := pawns[1]
	a.global_position = Vector3(20, 0.2, 20)
	b.global_position = Vector3(20, 0.2, 26)
	for p in pawns:
		p.move_and_slide()
	for i in 3:
		await get_tree().physics_frame
	var sight := brains[0]
	sight.los_ttl = BotBrain.new().los_ttl
	sight.los_cache = true
	# A fresh frame, so the first probe is a real one even with a TTL above one tick.
	await get_tree().physics_frame
	_ok(sight._can_see(b), "bot 0 sees bot 1 across the open floor")
	# The wall slides in front of bot 1; the physics world picks it up on the next frame.
	_blink.global_position = Vector3(20, 1.5, 23)
	await get_tree().physics_frame
	var late := 0
	while sight._can_see(b):
		late += 1
		if late > 10:
			break
		await get_tree().physics_frame
	_ok(late <= sight.los_ttl, "and loses it within the TTL (%d ticks late, ttl %d)" % [late, sight.los_ttl])
	_blink.global_position = Vector3(0, 1.5, 40)


func _done() -> void:
	set_physics_process(false)
	print("BOT PERF CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in fail_msgs:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
