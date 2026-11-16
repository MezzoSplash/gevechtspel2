extends Node
## #268. The bot's state is one enum, and a chase that escalates can never be left half-set.
##   hunt on no LOS · stuck flips the flank, stuck again goes direct · a new target starts on the
##   flank again · fighting only with line of sight · low HP breaks off.
##   ./run.sh --headless res://tools/check_bot_state.tscn   → "BOT STATE CHECK OK"
var fails := 0
var fail_msgs: Array[String] = []
var bot: Player
var near: Player
var far: Player
var brain: BotBrain
var wall: StaticBody3D
var _phase := "settle"
var _ticks := 0
var _fight_without_sight := false
var _fight_during_hunt := false
var _ammo_before := 0
var _dist_before := 0.0
const WALL_Z := -4.0


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


## A pawn parked outside the world: not a target, not visible, still alive for the tick.
func _park(p: Player) -> void:
	p.global_position = Vector3(p.global_position.x, -60.0, p.global_position.z)


func _wake(p: Player, at: Vector3) -> void:
	p.hp = Player.MAX_HP
	p.velocity = Vector3.ZERO
	p.global_position = at


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	Game.bot_difficulty = Game.BOT_HARD # omniscient: any enemy is a target, only sight decides a fight
	_body(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	# Chest high, so the head-to-head ray is blocked but the bot is not boxed in.
	wall = _body(Vector3(8, 2.4, 0.4), Vector3(0, 1.2, WALL_Z))
	bot = _pawn(-1, Vector3(0, 0.2, 0))
	near = _pawn(-2, Vector3(0, 0.2, -9))
	far = _pawn(-3, Vector3(0, 0.2, -9))
	_park(far)
	brain = BotBrain.new()
	brain.setup(bot, null)
	bot.weapon.ammo = 30
	bot.weapon._reload_left = 0.0
	_phase = "settle"


func _settle(next: String) -> void:
	bot.move_and_slide()
	_ticks += 1
	if not bot.is_on_floor() and _ticks <= 40:
		return
	_ticks = 0
	bot.velocity = Vector3.ZERO
	_phase = next


func _physics_process(delta: float) -> void:
	match _phase:
		"settle":
			_settle("hunt")
		"hunt":
			_tick_hunt(delta)
		"switch":
			_tick_switch(delta)
		"prep_fight":
			_tick_prep_fight(delta)
		"fight":
			_tick_fight(delta)
		"hunt_again":
			_tick_hunt_again(delta)
		"flee":
			_tick_flee(delta)


## A wall between them: it hunts, never fights, and its first leg is the flank.
func _tick_hunt(delta: float) -> void:
	brain.physics_tick(delta)
	_ticks += 1
	if brain.state == BotBrain.State.FIGHT:
		_fight_without_sight = true
	if _ticks < 8:
		return
	_ok(not _fight_without_sight, "no line of sight: never enters FIGHT")
	_ok(brain.state == BotBrain.State.HUNT_FLANK, "hunts the flank first (%s)" % _state_name(brain.state))
	var at := near.global_position
	var before := brain._flank_point(at) - at
	var angle_before := rad_to_deg(brain._flank_angle)
	# One stuck: the other side of the enemy, still a flank.
	brain._on_hunt_stuck()
	var after := brain._flank_point(at) - at
	_ok(before.dot(after) < 0.0, "stuck once walks to the other side (%.0f deg -> %.0f deg)" % [
		angle_before, rad_to_deg(brain._flank_angle)])
	_ok(brain.state == BotBrain.State.HUNT_FLANK, "and stays a flank (%s)" % _state_name(brain.state))
	# Twice: the ring point was useless, so it goes at the enemy's feet.
	brain._on_hunt_stuck()
	_ok(brain.state == BotBrain.State.HUNT_DIRECT, "stuck twice goes direct (%s)" % _state_name(brain.state))
	# And a third stuck must not re-flank and forget the direct chase.
	brain._on_hunt_stuck()
	_ok(brain.state == BotBrain.State.HUNT_DIRECT, "a third stuck keeps the direct chase (%s)" % _state_name(brain.state))
	_arm_switch()


## A new target after a direct chase starts on the flank again: the old line is not reused.
func _arm_switch() -> void:
	_park(near)
	_wake(far, Vector3(-3, 0.2, -9))
	brain._retarget_t = 0.0
	_ticks = 0
	_phase = "switch"


func _tick_switch(delta: float) -> void:
	brain.physics_tick(delta)
	_ticks += 1
	if _ticks < 6:
		return
	_ok(brain._target == far, "the closer pawn is the new target")
	_ok(brain.state == BotBrain.State.HUNT_FLANK,
		"a target switch drops the direct chase (%s)" % _state_name(brain.state))
	_ok(not brain._flank_flipped, "and the peer's own flank side is restored")
	_arm_fight()


## Wall gone, enemy in range: FIGHT, and it spends ammo.
func _arm_fight() -> void:
	wall.collision_layer = 0 # a layer change takes a physics frame to leave the ray query
	_ticks = 0
	_phase = "prep_fight"


func _tick_prep_fight(_delta: float) -> void:
	# Burn a few frames so the disabled wall is really out of the space state.
	_ticks += 1
	if _ticks < 4:
		return
	_wake(far, Vector3(-3, 0.2, -7))
	brain._target = null
	brain._retarget_t = 0.0
	brain._acquire_left = 0.0
	brain._burst_left = 0
	brain._burst_pause = 0.0
	bot.weapon.ammo = 30
	bot.weapon._reload_left = 0.0
	_ammo_before = bot.weapon.ammo
	_ticks = 0
	_phase = "fight"


func _tick_fight(delta: float) -> void:
	brain.physics_tick(delta)
	_ticks += 1
	if brain.state == BotBrain.State.FIGHT:
		_ok(true, "line of sight inside gun range: fights (%s)" % _state_name(brain.state))
		_ok(bot.weapon.ammo < _ammo_before, "and shoots (%d -> %d rounds)" % [_ammo_before, bot.weapon.ammo])
		_arm_hunt_again()
		return
	if _ticks > 40:
		_ok(false, "clear line of sight inside gun range never became a fight (%s)" % _state_name(brain.state))
		_arm_hunt_again()


func _arm_hunt_again() -> void:
	wall.collision_layer = 1
	_ticks = 0
	_phase = "hunt_again"


func _tick_hunt_again(delta: float) -> void:
	_ticks += 1
	if _ticks < 4:
		return
	brain.physics_tick(delta)
	if brain.state == BotBrain.State.FIGHT:
		_fight_during_hunt = true
	if _ticks < 20:
		return
	_ok(not _fight_during_hunt, "wall back: stops fighting")
	_ok(brain.state == BotBrain.State.HUNT_FLANK, "and hunts again (%s)" % _state_name(brain.state))
	_arm_flee()


## Low HP after a hit: break off, and get further away.
func _arm_flee() -> void:
	# Open floor, so a wall from the hunt phase cannot be what keeps the gap from growing.
	bot.global_position = Vector3(0, 0.2, 0)
	bot.velocity = Vector3.ZERO
	brain._home = bot.global_position
	brain._stuck_pos = bot.global_position
	Game.set_hp(bot, 30.0)
	brain._retreat_cd = 0.0
	brain._hurt_retreat_left = 0.0
	brain._threat = null
	brain._threat_left = 0.0
	brain.note_threat(far)
	_ok(brain.state == BotBrain.State.RETREAT, "low HP breaks off (%s)" % _state_name(brain.state))
	_dist_before = bot.global_position.distance_to(far.global_position)
	_ticks = 0
	_phase = "flee"


func _tick_flee(delta: float) -> void:
	brain.physics_tick(delta)
	_ticks += 1
	if _ticks < 30:
		return
	var now := bot.global_position.distance_to(far.global_position)
	_ok(now > _dist_before + 1.5, "and sprints away from the shooter (%.2f m -> %.2f m)" % [_dist_before, now])
	_done()


func _state_name(s: int) -> String:
	return BotBrain.State.keys()[s]


func _done() -> void:
	set_physics_process(false)
	print("BOT STATE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in fail_msgs:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
