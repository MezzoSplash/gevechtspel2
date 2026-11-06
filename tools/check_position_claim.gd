extends Node
## #B1 headless: the server does not believe the position a client claims. A pawn may only be where it
## could have reached since the last accepted claim; anything further is refused (and the client gets
## one correction). Without this a modified client teleports and shoots from there.
##   godot --headless --path . res://tools/check_position_claim.tscn   → "POSITION CLAIM CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.set_physics_process(false)
	add_child(p)
	# A remote human: not this machine's pawn, and not a bot.
	p.peer_id = 7
	p.position = Vector3.ZERO
	p.is_dead = false
	p._net_pos_ms = Time.get_ticks_msec()

	# A normal snapshot step is accepted.
	p._receive_net_pos(Vector3(0.4, 0.0, 0.4))
	_ok(p.position.distance_to(Vector3(0.4, 0.0, 0.4)) < 0.01, "a 0.6 m step is accepted")

	# A teleport across the map is refused: the pawn stays where the server has it.
	p._receive_net_pos(Vector3(120.0, 0.0, 120.0))
	_ok(p.position.distance_to(Vector3(0.4, 0.0, 0.4)) < 0.01,
		"a 170 m teleport is refused (still at %.1f, %.1f)" % [p.position.x, p.position.z])

	# The budget cannot pile up into a slow teleport: a second claim right after is judged from the
	# refused one, not from the last accepted position.
	p._receive_net_pos(Vector3(0.4, 0.0, 0.4))
	p._receive_net_pos(Vector3(120.0, 0.0, 120.0))
	_ok(p.position.distance_to(Vector3(0.4, 0.0, 0.4)) < 0.01, "a second teleport is refused as well")

	# Fast but real: 18 m/s for half a second is accepted.
	p._net_pos_ms = Time.get_ticks_msec() - 500
	p._receive_net_pos(Vector3(0.4, 0.0, 9.4))
	_ok(p.position.distance_to(Vector3(0.4, 0.0, 9.4)) < 0.01, "9 m in half a second is accepted (18 m/s)")

	# Falling hard is fine, rising out of nowhere is not.
	var base := p.position
	p._net_pos_ms = Time.get_ticks_msec() - 200
	p._receive_net_pos(base + Vector3(0.0, -6.0, 0.0))
	_ok(p.position.distance_to(base + Vector3(0.0, -6.0, 0.0)) < 0.01, "a 6 m fall in 200 ms is accepted")
	var low := p.position
	p._net_pos_ms = Time.get_ticks_msec() - 200
	p._receive_net_pos(low + Vector3(0.0, 40.0, 0.0))
	_ok(p.position.distance_to(low) < 0.01, "a 40 m jump up in 200 ms is refused")

	# A dead pawn accepts anything: that is a respawn.
	p.is_dead = true
	p._receive_net_pos(Vector3(-40.0, 2.0, -40.0))
	_ok(p.position.distance_to(Vector3(-40.0, 2.0, -40.0)) < 0.01, "a dead pawn accepts a respawn position")
	p.is_dead = false

	# A correction from the server is taken as the truth.
	p.apply_position_correction(Vector3(3.0, 1.0, -3.0))
	_ok(p.position.distance_to(Vector3(3.0, 1.0, -3.0)) < 0.01, "the server correction snaps the pawn back")

	print("POSITION CLAIM CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
