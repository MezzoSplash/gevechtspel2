extends Node
## Bot awareness, headless and without a match: a bot that is not omniscient only knows an enemy it has
## seen, was shot by or heard; it remembers the last spot for the profile's `memory` seconds and then forgets.
## Hard stays omniscient (how bots played before awareness existed).
##   godot --headless res://tools/check_bot_aware.tscn   → "BOT AWARE CHECK OK"
var fails := 0
var fail_msgs: Array[String] = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1
		fail_msgs.append(msg)


func _pawn(id: int) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = id
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	return p


func _enemy(pos: Vector3) -> Node3D:
	var e := Node3D.new()
	add_child(e)
	e.global_position = pos
	return e


func _ready() -> void:
	var old_skill: int = Game.bot_difficulty
	var easy: Dictionary = Game.BOT_PROFILES[Game.BOT_EASY]
	var med: Dictionary = Game.BOT_PROFILES[Game.BOT_MEDIUM]
	var hard: Dictionary = Game.BOT_PROFILES[Game.BOT_HARD]
	_ok(hard.omni and not med.omni and not easy.omni, "only Hard is omniscient")
	_ok(easy.memory < med.memory and easy.hear < med.hear, "Easy remembers less and hears less than Medium")

	# Medium: knows nothing until it sees, is shot by or hears someone.
	Game.bot_difficulty = Game.BOT_MEDIUM
	var brain := BotBrain.new()
	var foe := _enemy(Vector3(10, 0, 0))
	_ok(not brain._knows(foe), "Medium does not know an enemy it has not noticed")
	brain._remember(foe, Vector3(4, 0, 4))
	_ok(brain._knows(foe), "after noticing, the enemy is known")
	foe.global_position = Vector3(50, 0, 0)
	_ok(brain._goal_pos(foe).is_equal_approx(Vector3(4, 0, 4)),
		"the bot heads for the last known spot, not for where the enemy really is")
	brain._tick_memory(float(med.memory) - 0.5)
	_ok(brain._knows(foe), "still known just before the memory runs out")
	brain._tick_memory(1.0)
	_ok(not brain._knows(foe), "forgotten once the memory has run out")

	# Seeing the enemy again refreshes the memory.
	brain._remember(foe, Vector3(1, 0, 1))
	brain._tick_memory(float(med.memory) - 0.5)
	brain._remember(foe, Vector3(2, 0, 2))
	brain._tick_memory(float(med.memory) - 0.5)
	_ok(brain._knows(foe) and brain._goal_pos(foe).is_equal_approx(Vector3(2, 0, 2)),
		"a fresh sighting resets the timer and moves the spot")

	# _forget drops the enemy at once.
	brain._forget(foe)
	_ok(not brain._knows(foe), "_forget drops the enemy")

	# A freed pawn is dropped without an error.
	var gone := _enemy(Vector3.ZERO)
	brain._remember(gone, Vector3.ZERO)
	gone.free()
	brain._tick_memory(0.0)
	_ok(brain._known.is_empty(), "a freed pawn leaves the memory")

	# Easy forgets sooner.
	Game.bot_difficulty = Game.BOT_EASY
	brain._remember(foe, Vector3(3, 0, 3))
	brain._tick_memory(float(easy.memory) + 0.1)
	_ok(not brain._knows(foe), "Easy has forgotten after its (shorter) memory")

	# Hard: knows everyone, always at the real position, and keeps no memory.
	Game.bot_difficulty = Game.BOT_HARD
	var b2 := BotBrain.new()
	foe.global_position = Vector3(30, 0, 5)
	_ok(b2._knows(foe), "Hard knows an enemy it never saw")
	b2._remember(foe, Vector3(1, 0, 1))
	_ok(b2._known.is_empty() and b2._goal_pos(foe).is_equal_approx(Vector3(30, 0, 5)),
		"Hard keeps no memory and aims for the real position")

	# Hearing depends on a shot marking the pawn. On a dedicated server there is no sound, so the server
	# marks it in request_weapon_fire; the weapon path (a bot's own shot) has to do it too.
	var gunner := _pawn(21)
	gunner.last_shot_ms = -100000
	gunner.mark_shot()
	_ok(Time.get_ticks_msec() - gunner.last_shot_ms < 500,
		"Player.mark_shot() stamps the shot (what the server calls for a remote human)")
	gunner.last_shot_ms = -100000
	gunner.weapon.play_fire_sfx()
	_ok(Time.get_ticks_msec() - gunner.last_shot_ms < 500,
		"a fired weapon stamps its pawn (the bot path, and every machine that plays the shot)")
	gunner.queue_free()

	Game.bot_difficulty = old_skill
	print("BOT AWARE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	for m in fail_msgs:
		print("FAILED: %s" % m)
	get_tree().quit(1 if fails > 0 else 0)
