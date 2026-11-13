extends Node
## #B2 headless: a claimed movement trick only counts when the server can back it up. The client owns
## its pawn, so move_fx and walljumps arrive as claims — and in the style modes those claims are points,
## so a modified client used to farm WALLRUN / DIVE / ROLL / WALLJUMP by lying.
## This tests the gate itself (`Player._claim_backed`): it must say no to a lie and yes to a real move.
##   godot --headless --path . res://tools/check_trick_claims.tscn   → "TRICK CLAIMS CHECK OK"
const BASE := Vector3(0, 200, 0)
var fails := 0
var p: Player


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


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


func _ready() -> void:
	# The tree is still being set up on the first _ready tick: wait one frame before adding bodies.
	await get_tree().process_frame
	# A floor, and a wall at x = 2.5 as seen from a pawn at 1.9 (0.6 m away).
	_box(BASE + Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	_box(BASE + Vector3(3.0, 3.0, 0), Vector3(1, 20, 40))
	await _frames(2)

	p = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.set_physics_process(false)
	add_child(p)
	p.peer_id = 7 # a remote human: nothing it claims is trusted
	p.is_dead = false
	await _frames(2)

	# --- wallrun: air + speed + a wall ---
	p.global_position = BASE + Vector3(-10, 1.0, 0)
	p._style.in_air = false
	p._obs_speed = 0.0
	_ok(not p._claim_backed(Player.MOVE_WALLRUN), "wallrun: standing still in the open is refused")
	p._obs_speed = Player.SPRINT_SPEED
	_ok(not p._claim_backed(Player.MOVE_WALLRUN), "wallrun: running in the open is refused (no wall)")
	p.global_position = BASE + Vector3(1.9, 3.0, 0)
	_ok(not p._claim_backed(Player.MOVE_WALLRUN), "wallrun: beside a wall on the ground is refused")
	p._style.in_air = true
	p._obs_speed = Player.SPRINT_SPEED
	_ok(p._claim_backed(Player.MOVE_WALLRUN), "wallrun: in the air along a wall is believed")
	p._obs_speed = Player.WALLRUN_KEEP_SPEED * 0.5
	_ok(not p._claim_backed(Player.MOVE_WALLRUN), "wallrun: hanging still by a wall is refused")

	# --- dive: momentum or real air time ---
	p.global_position = BASE + Vector3(-10, 1.0, 0)
	p._style.in_air = false
	p._style.air_time = 0.0
	p._obs_speed = 0.0
	_ok(not p._claim_backed(Player.MOVE_DIVE), "dive: standing still is refused")
	p._style.air_time = 0.4
	_ok(p._claim_backed(Player.MOVE_DIVE), "dive: a real fall is believed")
	p._style.air_time = 0.0
	p._obs_speed = Player.SPRINT_SPEED
	_ok(p._claim_backed(Player.MOVE_DIVE), "dive: sprint speed is believed")

	# --- roll: needs momentum ---
	p._obs_speed = 0.0
	_ok(not p._claim_backed(Player.MOVE_ROLL), "roll: standing still is refused")
	p._obs_speed = Player.WALK_SPEED
	_ok(p._claim_backed(Player.MOVE_ROLL), "roll: a walk's worth of speed is believed")

	# --- nothing else is ever backed ---
	_ok(not p._claim_backed(Player.MOVE_NONE), "no claim on a plain move")

	print("TRICK CLAIMS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
