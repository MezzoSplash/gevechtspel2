class_name PhysFx
extends Node
## Local-only physics eye candy: death tumbles and shell casings. Nothing here touches the
## simulation or the network, every machine makes its own, and the server (dedicated) makes none.
## Both are capped and pooled. Graphics Low: no casings, shorter tumble.

# Death tumble
const CORPSE_MAX := 6
const TUMBLE_SPEED_SHOT := 3.2 # m/s sideways push from a bullet
const TUMBLE_SPEED_BLAST := 9.0 # m/s at the blast centre
const TUMBLE_BLAST_RANGE := 6.0
const TUMBLE_LIFT := 2.6
const TUMBLE_SPIN := 4.5 # rad/s of the fall (0 → lying down is pi/2)
const TUMBLE_REST := 1.4 # s on the floor before it fades
const TUMBLE_FADE := 0.6
const TUMBLE_GRAVITY := 22.0
const TUMBLE_BOUNCE := 0.3
const TUMBLE_FRICTION := 5.0

# Shell casings
const CASING_MAX_HIGH := 28
const CASING_MAX_MEDIUM := 12 # Low: none
const CASING_LIFE := 2.2
const CASING_FADE := 0.4
const CASING_BOUNCES := 3
const CASING_RESTITUTION := 0.35
const CASING_GRAVITY := 18.0

static var _inst: PhysFx

var _corpses: Array = [] # {node, vel, angle, spin, axis, yaw_basis, age, rest, lying}
var _casings: Array = [] # {node, vel, spin, age, bounces, still}
var _casing_mesh: Dictionary = {}
var _casing_mat: Dictionary = {}


static func get_fx() -> PhysFx:
	if is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or Game.is_dedicated:
		return null
	_inst = PhysFx.new()
	_inst.name = "PhysFx"
	tree.current_scene.add_child(_inst)
	return _inst


static func clear() -> void:
	if is_instance_valid(_inst):
		_inst.reset()


func reset() -> void:
	for c in _corpses:
		(c.node as Node).queue_free()
	for c in _casings:
		(c.node as Node).queue_free()
	_corpses.clear()
	_casings.clear()


# ---------------------------------------------------------------- death tumble

## Copy of the pawn's drawn body that falls over, away from `from_pos` (shooter or blast).
static func tumble(p: Player, from_pos: Vector3) -> void:
	var fx := get_fx()
	if fx == null or p.body_mesh == null:
		return
	fx._spawn_corpse(p, from_pos)


func _spawn_corpse(p: Player, from_pos: Vector3) -> void:
	while _corpses.size() >= CORPSE_MAX:
		var old: Dictionary = _corpses.pop_front()
		(old.node as Node).queue_free()
	var centre := p.global_position + Vector3(0.0, 0.9, 0.0)
	var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var speed := TUMBLE_SPEED_SHOT * 0.3
	if from_pos.is_finite():
		var flat := centre - from_pos
		var dist := flat.length()
		flat.y = 0.0
		if flat.length_squared() > 0.0001:
			away = flat
		if dist < TUMBLE_BLAST_RANGE:
			speed = TUMBLE_SPEED_SHOT + TUMBLE_SPEED_BLAST * (1.0 - dist / TUMBLE_BLAST_RANGE)
		else:
			speed = TUMBLE_SPEED_SHOT
	away = away.normalized()
	var root := Node3D.new()
	root.name = "Corpse"
	add_child(root)
	root.global_position = centre
	var body := p.body_mesh.duplicate() as Node3D
	body.visible = true
	root.add_child(body)
	body.transform = Transform3D(p.body_mesh.transform.basis, p.body_mesh.position - Vector3(0.0, 0.9, 0.0))
	var yaw_basis := Basis(Vector3.UP, p.rotation.y)
	root.basis = yaw_basis
	_corpses.append({
		"node": root, "vel": away * speed + Vector3.UP * TUMBLE_LIFT * (0.5 + speed / (TUMBLE_SPEED_SHOT + TUMBLE_SPEED_BLAST)),
		"angle": 0.0, "spin": TUMBLE_SPIN * (0.6 + speed / 10.0), "axis": Vector3.UP.cross(away).normalized(),
		"yaw": yaw_basis, "age": 0.0, "rest": 0.0, "grounded": false,
	})


# ---------------------------------------------------------------- casings

static func eject(weapon: Node3D, kind: StringName, muzzle_local: Vector3) -> void:
	var cap := CASING_MAX_HIGH if Game.gfx_quality >= 2 else (CASING_MAX_MEDIUM if Game.gfx_quality == 1 else 0)
	if cap <= 0 or weapon == null or not weapon.is_visible_in_tree():
		return
	var fx := get_fx()
	if fx == null:
		return
	fx._spawn_casing(weapon, kind, muzzle_local, cap)


func _mesh_for(kind: StringName) -> Mesh:
	if not _casing_mesh.has(kind):
		var m := BoxMesh.new()
		match kind:
			&"shotgun": m.size = Vector3(0.02, 0.02, 0.055)
			&"sniper": m.size = Vector3(0.016, 0.016, 0.07)
			&"pistol", &"smg": m.size = Vector3(0.010, 0.010, 0.026)
			_: m.size = Vector3(0.012, 0.012, 0.04)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.15, 0.12) if kind == &"shotgun" else Color(0.82, 0.62, 0.24)
		mat.metallic = 0.0 if kind == &"shotgun" else 0.6
		mat.roughness = 0.45
		m.material = mat
		_casing_mesh[kind] = m
	return _casing_mesh[kind]


func _spawn_casing(weapon: Node3D, kind: StringName, muzzle_local: Vector3, cap: int) -> void:
	var node: MeshInstance3D
	if _casings.size() >= cap:
		node = (_casings.pop_front() as Dictionary).node
	else:
		node = MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	node.mesh = _mesh_for(kind)
	node.scale = Vector3.ONE
	node.visible = true
	var gb := weapon.global_basis
	var right := gb.x.normalized()
	var fwd := -gb.z.normalized()
	node.global_position = weapon.to_global(muzzle_local * 0.35 + Vector3(0.03, 0.03, 0.0))
	node.global_basis = Basis.looking_at(right, Vector3.UP)
	var vel := right * randf_range(1.6, 2.6) + Vector3.UP * randf_range(1.4, 2.4) - fwd * randf_range(0.0, 0.5)
	var player := weapon.owner as Player
	if player:
		vel += player.velocity * 0.4
	_casings.append({
		"node": node, "vel": vel,
		"spin": Vector3(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0), randf_range(-30.0, 30.0)),
		"age": 0.0, "bounces": 0, "still": false,
	})


# ---------------------------------------------------------------- sim

func _physics_process(delta: float) -> void:
	_step_corpses(delta)
	_step_casings(delta)


func _step_corpses(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var i := _corpses.size() - 1
	while i >= 0:
		var c: Dictionary = _corpses[i]
		var root := c.node as Node3D
		c.age += delta
		var vel: Vector3 = c.vel
		vel.y -= TUMBLE_GRAVITY * delta
		var from := root.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + vel * delta + Vector3.DOWN * 0.35)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			root.global_position = from + vel * delta
			c.grounded = false
		else:
			var n: Vector3 = hit.normal
			if n.y > 0.5:
				root.global_position = Vector3(hit.position.x, hit.position.y + 0.3, hit.position.z)
				if vel.y < -2.0 and not c.grounded:
					vel.y = -vel.y * TUMBLE_BOUNCE
				else:
					vel.y = 0.0
				var h := Vector3(vel.x, 0.0, vel.z)
				h = h.move_toward(Vector3.ZERO, TUMBLE_FRICTION * delta)
				vel = Vector3(h.x, vel.y, h.z)
				c.grounded = true
			else:
				root.global_position = hit.position + n * 0.35
				vel = vel.bounce(n) * 0.4
		c.vel = vel
		# Fall over: angle 0 (standing) → pi/2 (lying), a small rebound at the floor.
		var angle: float = c.angle
		var spin: float = c.spin
		if angle < PI * 0.5 or spin > 0.0:
			angle += spin * delta
			if angle >= PI * 0.5:
				angle = PI * 0.5
				spin = -spin * 0.22 if absf(spin) > 1.0 else 0.0
			elif angle < 0.0:
				angle = 0.0
				spin = 0.0
			elif c.grounded and spin < 0.0:
				spin = minf(spin + 12.0 * delta, 0.0) # the rebound dies out
		c.angle = angle
		c.spin = spin
		root.basis = Basis(c.axis, angle) * (c.yaw as Basis)
		var life_after: float = c.age - (0.3 if Game.gfx_quality == 0 else 0.0)
		if c.grounded and absf(vel.x) + absf(vel.z) < 0.3:
			c.rest += delta
		var fade: float = 0.0
		var rest_limit: float = TUMBLE_REST * (0.5 if Game.gfx_quality == 0 else 1.0)
		if c.rest > rest_limit:
			fade = clampf((c.rest - rest_limit) / TUMBLE_FADE, 0.0, 1.0)
		if life_after > 8.0:
			fade = 1.0
		if fade > 0.0:
			_set_fade(root, fade)
		if fade >= 1.0:
			root.queue_free()
			_corpses.remove_at(i)
		i -= 1


func _set_fade(n: Node, t: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = t
	for ch in n.get_children():
		_set_fade(ch, t)


func _step_casings(delta: float) -> void:
	if _casings.is_empty():
		return
	var space := get_viewport().world_3d.direct_space_state
	var i := _casings.size() - 1
	while i >= 0:
		var c: Dictionary = _casings[i]
		var node := c.node as MeshInstance3D
		c.age += delta
		if c.age >= CASING_LIFE:
			node.queue_free()
			_casings.remove_at(i)
			i -= 1
			continue
		if c.age > CASING_LIFE - CASING_FADE:
			node.scale = Vector3.ONE * clampf((CASING_LIFE - c.age) / CASING_FADE, 0.01, 1.0)
		if not c.still:
			var vel: Vector3 = c.vel
			vel.y -= CASING_GRAVITY * delta
			var from := node.global_position
			var q := PhysicsRayQueryParameters3D.create(from, from + vel * delta)
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				node.global_position = from + vel * delta
				node.rotate_object_local(Vector3.RIGHT, c.spin.x * delta)
				node.rotate_object_local(Vector3.UP, c.spin.y * delta)
				node.rotate_object_local(Vector3.FORWARD, c.spin.z * delta)
			else:
				c.bounces += 1
				node.global_position = hit.position + hit.normal * 0.006
				vel = vel.bounce(hit.normal) * CASING_RESTITUTION
				c.spin = (c.spin as Vector3) * 0.4
				if c.bounces >= CASING_BOUNCES or vel.length() < 0.6:
					c.still = true
					vel = Vector3.ZERO
			c.vel = vel
		i -= 1
