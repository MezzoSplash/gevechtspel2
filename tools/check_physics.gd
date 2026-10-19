extends Node3D
## Headless checks for the physics-feel pass: knockback math and falloff, car kick, death tumble,
## casing cap and quality gating. Run:
##   godot --headless --path . res://tools/check_physics.tscn
## Prints "PHYSICS CHECK OK" or "FAILED".

var fails := 0


func _ready() -> void:
	await get_tree().physics_frame
	_floor()
	_math()
	await _car_kick()
	await _tumble()
	await _casings()
	print("PHYSICS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL ", msg)


func _floor() -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	s.shape = shape
	b.add_child(s)
	add_child(b)
	b.global_position = Vector3(0, -0.5, 0)


func _math() -> void:
	var c := Vector3(1.0, 1.0, 0.0)
	var near := Knockback.impulse_for(Vector3(0, 1, 0), c, 5.5, 14.0, 1.0, Knockback.MAX_PUSH)
	var far := Knockback.impulse_for(Vector3(0, 1, 0), Vector3(4.0, 1.0, 0.0), 5.5, 14.0, 1.0, Knockback.MAX_PUSH)
	var out := Knockback.impulse_for(Vector3(0, 1, 0), Vector3(6.0, 1.0, 0.0), 5.5, 14.0, 1.0, Knockback.MAX_PUSH)
	var own := Knockback.impulse_for(Vector3(0, 1, 0), c, 5.5, 14.0, Knockback.SELF_MULT, Knockback.MAX_PUSH)
	var point_blank := Knockback.impulse_for(Vector3(0, 1, 0), Vector3(0, 1.0, 0.0), 5.5, 14.0, 1.0, Knockback.MAX_PUSH)
	print("knockback near %.2f far %.2f out %.2f own %.2f point-blank %.2f (y %.2f)" % [near.length(), far.length(), out.length(), own.length(), point_blank.length(), point_blank.y])
	_ok(near.length() > far.length() and far.length() > 0.0, "falloff with distance")
	_ok(out == Vector3.ZERO, "no push outside the radius")
	_ok(own.length() < near.length(), "self blast is weaker")
	_ok(near.length() <= Knockback.MAX_PUSH + 0.001, "cap")
	_ok(near.y > 0.3 * near.length() * 0.9, "always lifts")
	_ok(point_blank.y > 0.0, "point blank goes up")


func _car_kick() -> void:
	var car := RcXd.new()
	car.authority_sim = true
	car.owner_peer = -77
	car.net_id = 7001
	add_child(car)
	car.global_position = Vector3(0, 0.3, 0)
	car.life = 99.0
	for i in 20:
		await get_tree().physics_frame
	var y0 := car.global_position.y
	car.add_kick(Vector3(5, 7, 0))
	var peak := y0
	var x_end := 0.0
	for i in 60:
		await get_tree().physics_frame
		peak = maxf(peak, car.global_position.y)
	x_end = car.global_position.x
	print("car kick: peak %.2f above floor %.2f, moved x %.2f" % [peak, y0, x_end])
	_ok(peak - y0 > 0.5, "car leaves the floor after a blast")
	_ok(x_end > 1.0, "car is pushed sideways")
	_ok(car.global_position.y < y0 + 0.2, "car lands again")
	car.shutdown(false)


func _tumble() -> void:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.is_bot = true
	add_child(p)
	p.global_position = Vector3(0, 0, 0)
	await get_tree().physics_frame
	for i in PhysFx.CORPSE_MAX + 3:
		PhysFx.tumble(p, Vector3(-2.0, 1.0, 0.0))
	var fx := PhysFx.get_fx()
	_ok(fx != null, "PhysFx exists")
	if fx == null:
		return
	_ok(fx._corpses.size() == PhysFx.CORPSE_MAX, "corpse cap (%d)" % fx._corpses.size())
	var c: Dictionary = fx._corpses[fx._corpses.size() - 1]
	var x0 := (c.node as Node3D).global_position.x
	for i in 90:
		await get_tree().physics_frame
	var n := c.node as Node3D
	_ok(is_instance_valid(n) and n.global_position.x > x0 + 0.5, "body is pushed away from the source")
	_ok(absf(c.angle - PI * 0.5) < 0.2, "body ends lying down (%.2f)" % float(c.angle))
	_ok(n.global_position.y < 0.6 and n.global_position.y > 0.0, "body rests on the floor (y %.2f)" % n.global_position.y)
	for i in 240:
		await get_tree().physics_frame
	_ok(fx._corpses.is_empty(), "corpses fade out and are freed")
	p.velocity = Vector3.ZERO
	p.add_knockback(Vector3(6, 5, 0))
	_ok(p.velocity.is_equal_approx(Vector3(6, 5, 0)) and p._kb_t > 0.0, "player knockback adds velocity")
	p.is_dead = true
	p.velocity = Vector3.ZERO
	p.add_knockback(Vector3(6, 5, 0))
	_ok(p.velocity == Vector3.ZERO, "dead players are not pushed")
	p.queue_free()


func _casings() -> void:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.is_bot = true
	add_child(p)
	p.global_position = Vector3(0, 1.0, 0)
	await get_tree().physics_frame
	var w := p.weapon
	var fx := PhysFx.get_fx()
	Game.gfx_quality = 0
	for i in 5:
		PhysFx.eject(w, &"rifle", Vector3(0, 0, -0.5))
	_ok(fx._casings.is_empty(), "Low graphics: no casings")
	Game.gfx_quality = 2
	for i in 60:
		PhysFx.eject(w, &"rifle", Vector3(0, 0, -0.5))
	_ok(fx._casings.size() == PhysFx.CASING_MAX_HIGH, "casing cap High (%d)" % fx._casings.size())
	Game.gfx_quality = 1
	fx.reset()
	for i in 60:
		PhysFx.eject(w, &"rifle", Vector3(0, 0, -0.5))
	_ok(fx._casings.size() == PhysFx.CASING_MAX_MEDIUM, "casing cap Medium (%d)" % fx._casings.size())
	for i in 200:
		await get_tree().physics_frame
	_ok(fx._casings.is_empty(), "casings expire")
	Game.gfx_quality = 2
