extends Node
## #261. Every map has a kill_y. A pawn under it during the respawn grace is back on its spawn
## within one tick. After that grace the same fall is a death, even while spawn protection
## would still block a bullet, and the respawn puts the body back on that spawn.
##   ./run.sh --headless res://tools/check_void.tscn   → "VOID CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	for id in Maps.ORDER:
		var scene := load(str(Maps.info(id).scene)) as PackedScene
		var map := scene.instantiate()
		# Same resolution as Main._load_map: scene metadata wins, otherwise the registry.
		var y := float(map.get_meta(&"kill_y", Maps.kill_y(id)))
		_ok(y < 0.0 and y > -20.0, "%s kill_y is below the floor (%.1f)" % [id, y])
		_ok(is_equal_approx(y, Maps.kill_y(id)), "%s scene and Maps agree (%.1f)" % [id, y])
		map.free()
	await _fall()
	print("VOID CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _fall() -> void:
	Game.map_kill_y = Maps.kill_y(&"townhouses")
	var spawn := Vector3(2.0, 0.2, 3.0)
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = -7
	p.is_bot = true
	p.name = "bot7"
	p.position = spawn
	add_child(p)
	# A node added this frame is not in the physics list yet. One tick at the spawn, then the drop.
	await get_tree().physics_frame
	p._bot_brain = null
	p.global_position = Vector3(spawn.x, Game.map_kill_y - 4.0, spawn.z)
	p.velocity = Vector3(0, -8, 0)
	p._spawn_protect = Player.SPAWN_PROTECT
	await get_tree().physics_frame
	var back := p.global_position.distance_to(spawn)
	_ok(back < 0.15 and not p.is_dead, "under the plane in the grace: back on the spawn in one tick (%.2f m, dead %s)" % [back, p.is_dead])
	p.global_position = Vector3(spawn.x, Game.map_kill_y - 4.0, spawn.z)
	p.velocity = Vector3(0, -8, 0)
	# Past the one-second grace, still inside the 1.8 s spawn protection. A bullet would miss;
	# the plane has to kill or the body keeps falling.
	p._spawn_protect = Player.SPAWN_PROTECT - Player.VOID_GRACE - 0.05
	await get_tree().physics_frame
	_ok(p.is_dead, "under the plane after the grace: a fall death")
	await get_tree().create_timer(Player.RESPAWN_TIME + 0.15).timeout
	var home := p.global_position.distance_to(spawn)
	_ok(not p.is_dead and home < 0.15, "the death puts you back on the spawn (%.2f m, dead %s)" % [home, p.is_dead])
	var alive := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	alive.peer_id = -8
	alive.is_bot = true
	alive.name = "bot8"
	alive.position = Vector3(0, 0.2, 0)
	add_child(alive)
	await get_tree().physics_frame
	var held := alive.global_position
	await get_tree().physics_frame
	_ok(not alive.is_dead and alive.global_position.distance_to(held) < 0.5, "above the plane: stays put")
