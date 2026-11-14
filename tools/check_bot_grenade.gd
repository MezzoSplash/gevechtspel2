extends Node
## #271. A bot under a low ceiling does not throw: the arc would bounce the frag back.
## The same bot in the open does throw, and a blocked toss does not start the cooldown.
##   ./run.sh --headless res://tools/check_bot_grenade.tscn   → "BOT GRENADE CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _body(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
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
	p.position = at
	p.name = "Bot%d" % id
	add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	return p


func _ready() -> void:
	_body(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	var bot := _pawn(1, Vector3(0, 0.05, 0))
	var enemy := _pawn(2, Vector3(0, 0.05, -10))
	var brain := BotBrain.new()
	brain.pawn = bot
	bot.grenades = 2
	var ceiling := _body(Vector3(6, 0.4, 6), Vector3(0, 2.25, -1.5))
	await get_tree().physics_frame
	var dist := bot.global_position.distance_to(enemy.global_position)
	var blocked := _attempt(brain, enemy, dist)
	_ok(not blocked.threw and bot.grenades == 2, "under a low ceiling the bot keeps the frag")
	_ok(brain._nade_cd == 0.0, "a blocked toss does not start the cooldown (%.2f)" % brain._nade_cd)
	_ok(get_tree().get_nodes_in_group("grenade").is_empty(), "no grenade spawned into the ceiling")
	ceiling.queue_free()
	await get_tree().physics_frame
	bot.grenades = 2
	var open := _attempt(brain, enemy, dist)
	_ok(open.threw and bot.grenades == 1, "in the open the same toss leaves the hand")
	_ok(not get_tree().get_nodes_in_group("grenade").is_empty(), "a grenade exists after the open toss")
	_ok(brain._nade_cd > 0.0, "a thrown frag starts the cooldown")
	print("BOT GRENADE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## One call that gets past the chance roll. The seed makes that roll deterministic.
func _attempt(brain: BotBrain, enemy: Player, dist: float) -> Dictionary:
	var seed_n := _chance_seed()
	seed(seed_n)
	brain._nade_check = 0.0
	brain._nade_cd = 0.0
	var threw := brain._try_grenade(enemy, dist, 1.0)
	return {"threw": threw}


func _chance_seed() -> int:
	for s in 80:
		seed(s)
		if randf() <= BotBrain.NADE_CHANCE:
			return s
	return 0
