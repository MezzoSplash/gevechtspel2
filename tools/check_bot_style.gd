extends Node
## #267. A character is tactics, not difficulty: in a 10 s fight a holder keeps its distance while
## aggressive and chaos brawl up close (#285 review: only the holder holds). Plus: the slot mapping is
## stable, so a respawn keeps the character.
##   ./run.sh --headless res://tools/check_bot_style.tscn   → "BOT STYLE CHECK OK"
const TICKS := 600
const STANDOFF := 16.0
var fails := 0
var fail_msgs: Array[String] = []
var bot: Player
var enemy: Player
var brain: BotBrain


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
	p.name = "Bot%d" % -id
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	p.grenades = 0
	return p


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	Game.bot_difficulty = Game.BOT_HARD # omniscient: it always has the enemy as its target
	_body(Vector3(80, 1, 80), Vector3(0, -0.5, 0))
	bot = _pawn(-1, Vector3(0, 0.2, 0))
	# The shooter is armed, the target is not: it may die in the sim, it must not shoot back.
	bot.weapon.equip_loadout(0)
	enemy = _pawn(-2, Vector3(0, 0.2, STANDOFF))
	enemy.weapon.equip_loadout(0)
	enemy.weapon.ammo = 0
	enemy.set_physics_process(false)
	brain = BotBrain.new()
	brain.setup(bot, null)
	_run_after_settle()


func _run_after_settle() -> void:
	for i in 10:
		bot.move_and_slide()
		enemy.move_and_slide()
		await get_tree().physics_frame
	var aggressive := await _mean_distance(&"aggressive")
	var chaos := await _mean_distance(&"chaos")
	var holder := await _mean_distance(&"holder")
	print("  mean fighting distance over %d ticks: aggressive %.2f m, chaos %.2f m, holder %.2f m" % [
		TICKS, aggressive, chaos, holder])
	_ok(aggressive > 0.0 and chaos > 0.0 and holder > 0.0, "all three characters actually fought")
	_ok(holder > aggressive + 2.0, "the holder keeps %.1f m more distance than the aggressive bot" % (holder - aggressive))
	# Aggressive and chaos both brawl: the distance rule is a floor for them, not a preferred range.
	_ok(holder > chaos + 2.0, "and %.1f m more than chaos, which fights up close like the old bots" % (holder - chaos))
	var aggressive_front := await _front_fight(&"aggressive")
	var flanker_front := await _front_fight(&"flanker")
	print("  enemy facing us the whole time: first fight tick aggressive %d, flanker %d" % [
		aggressive_front["first"], flanker_front["first"]])
	_ok(flanker_front["first"] > aggressive_front["first"] + 30,
		"a front-facing enemy keeps the flanker out of the fight at least 0.5 s longer (%d vs %d)" % [
			aggressive_front["first"], flanker_front["first"]])
	_ok(flanker_front["first"] >= 0, "and the flanker does open fire once it has the angle or the patience")
	var on := await _ring_walk(0.5)
	var off := await _ring_walk(0.0)
	print("  standing on its own ring point for 1 s: %d new angles with the switch, %d without" % [
		on, off])
	_ok(on > off, "a reached ring point is left again because of the switch (%d vs %d new angles)" % [on, off])
	_slots()
	_done()


## One second of the flanker standing on its own ring point of a target it cannot attack
## (front-facing), with `flank_switch` forced to `switch_on`. The only thing that can move the ring
## angle there is the switch, so the turn count isolates it. Runs on a copy of the resource.
func _ring_walk(switch_on: float) -> int:
	_place()
	brain.setup(bot, null)
	brain.style = BotStyle.by_id(&"flanker").duplicate()
	brain.style.flank_switch = switch_on
	bot.weapon.equip_loadout(0)
	var at := brain._goal_pos(enemy)
	var ring := at + Vector3(cos(brain._flank_base), 0.0, sin(brain._flank_base)) * brain._fight_range()
	bot.global_position = ring + Vector3(0, 0.2, 0)
	bot.velocity = Vector3.ZERO
	brain._home = bot.global_position
	brain._stuck_pos = bot.global_position
	bot.move_and_slide()
	var turns := 0
	var last_angle := brain._flank_angle
	for i in 60:
		_keep_alive()
		enemy.look_at(bot.global_position, Vector3.UP)
		brain.physics_tick(1.0 / 60.0)
		if absf(wrapf(brain._flank_angle - last_angle, -PI, PI)) > 0.01:
			turns += 1
		last_angle = brain._flank_angle
		await get_tree().physics_frame
	return turns


## When does `style_id` first open fire on an enemy that faces it the whole window? The flanker
## circles and only fights from point blank or after its patience; everyone else fights at once.
func _front_fight(style_id: StringName) -> Dictionary:
	_place()
	brain.setup(bot, null)
	brain.style = BotStyle.by_id(style_id)
	bot.weapon.equip_loadout(0)
	var first := -1
	for i in TICKS:
		_keep_alive()
		enemy.look_at(bot.global_position, Vector3.UP) # never a side or a back view
		brain.physics_tick(1.0 / 60.0)
		if first < 0 and brain.state == BotBrain.State.FIGHT:
			first = i
		await get_tree().physics_frame
	return {"first": first}


func _place() -> void:
	bot.global_position = Vector3(0, 0.2, 0)
	enemy.global_position = Vector3(0, 0.2, STANDOFF)
	for p in [bot, enemy]:
		p.velocity = Vector3.ZERO
		p.hp = Player.MAX_HP
		p.is_dead = false
		p.move_and_slide()


## The window keeps both pawns alive and the shooter armed, so it measures the tactic and not a
## death or a reload.
func _keep_alive() -> void:
	bot.hp = Player.MAX_HP
	enemy.hp = Player.MAX_HP
	enemy.is_dead = false
	bot.is_dead = false
	bot.weapon.ammo = 30
	enemy.weapon.ammo = 0


## Mean distance while the bot is in a fight, over TICKS of the real brain. Both pawns are kept
## alive and armed every tick, so the window measures the tactic and not a reload or a death.
func _mean_distance(style_id: StringName) -> float:
	_place()
	brain.setup(bot, null)
	brain.style = BotStyle.by_id(style_id)
	bot.weapon.equip_loadout(0)
	var sum := 0.0
	var n := 0
	for i in TICKS:
		_keep_alive()
		brain.physics_tick(1.0 / 60.0)
		if brain.state == BotBrain.State.FIGHT:
			sum += bot.global_position.distance_to(enemy.global_position)
			n += 1
		await get_tree().physics_frame
	return sum / float(n) if n > 0 else -1.0


## The slot mapping has to be deterministic and stable: two bots of a lobby differ, one bot across
## two respawns does not.
func _slots() -> void:
	var seen := {}
	for id in [-1, -2, -3, -4]:
		var s := BotStyle.for_peer(id)
		seen[s.id] = true
	_ok(seen.size() == 4, "four bot slots get four different characters (%s)" % [seen.keys()])
	_ok(BotStyle.for_peer(-2).id == BotStyle.for_peer(-2).id, "a slot keeps its character on a respawn")
	_ok(BotStyle.for_peer(-1).id == BotStyle.for_peer(-5).id, "and the cycle repeats every four slots")
	_ok(BotStyle.by_id(&"flanker").flank_switch > 0.0, "the flanker keeps taking new angles on the ring")
	_ok(BotStyle.by_id(&"aggressive").slide_near > BotStyle.by_id(&"chaos").slide_near,
		"the aggressive bot slides from further out (%.0f vs %.0f m)" % [
			BotStyle.by_id(&"aggressive").slide_near, BotStyle.by_id(&"chaos").slide_near])
	_ok(BotStyle.by_id(&"holder").nade_chance == 0.0, "the holder throws no frags")
	_ok(BotStyle.by_id(&"holder").retreat_hp > BotStyle.by_id(&"aggressive").retreat_hp,
		"the aggressive bot gives up later (%.0f vs %.0f HP)" % [
			BotStyle.by_id(&"aggressive").retreat_hp, BotStyle.by_id(&"holder").retreat_hp])


func _done() -> void:
	set_physics_process(false)
	print("BOT STYLE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in fail_msgs:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
