class_name ImpactMarks
extends Node3D
## Bullet marks on world geometry: a small dark quad flat on the surface plus a tiny dust puff.
## Pure visuals, never on a dedicated server, never on players. Pooled: once POOL marks are out,
## the oldest one is reused, so heavy fire never adds nodes. Node /root/Game/ImpactMarks.

const POOL := 64
const PUFFS := 16
const LIFE := 2.0 # seconds a mark stays
const FADE := 0.6 # the last part of LIFE fades out
const SIZE := 0.13 # metres across
const ALPHA := 0.9
const LIFT := 0.006 # off the surface, against z-fighting
const PUFF_LIFE := 0.35
const WORLD_MASK := 1
const NET_SNAP := 0.25 # remote tracer end must be this close to a wall to leave a mark

var _quad: QuadMesh
var _marks: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _age := PackedFloat32Array()
var _next := 0
var _live := 0
var _puffs: Array[CPUParticles3D] = []
var _next_puff := 0


func _ready() -> void:
	set_process(false)


## A hit from this machine's own rays (local shots, bots on the authority).
func add(pos: Vector3, normal: Vector3, collider: Object = null) -> void:
	if Game.is_dedicated or not is_inside_tree():
		return
	if collider is Player or collider is RigidBody3D:
		return
	if normal.length_squared() < 0.0001:
		return
	if _marks.is_empty():
		_build()
	var n := normal.normalized()
	var i := _next
	_next = (_next + 1) % POOL
	if _age[i] < 0.0:
		_live += 1
	_age[i] = 0.0
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(-n, up).rotated(n, randf() * TAU)
	var mark := _marks[i]
	var size := randf_range(0.8, 1.2)
	mark.global_transform = Transform3D(basis.scaled(Vector3.ONE * size), pos + n * LIFT)
	_mats[i].albedo_color.a = ALPHA
	mark.visible = true
	_puff(pos + n * 0.02, n)
	set_process(true)


## Someone else's shot: only the tracer end is known, so find the wall (and its normal) with a ray.
func add_from_tracer(from: Vector3, to: Vector3) -> void:
	if Game.is_dedicated or not is_inside_tree():
		return
	var dir := to - from
	if dir.length_squared() < 0.0025:
		return
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(from, to + dir * NET_SNAP)
	query.collision_mask = WORLD_MASK
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.position as Vector3).distance_to(to) > NET_SNAP:
		return
	add(hit.position, hit.normal, hit.collider)


func clear() -> void:
	for i in _marks.size():
		_age[i] = -1.0
		_marks[i].visible = false
	for p in _puffs:
		p.emitting = false
	_live = 0
	set_process(false)


func _process(delta: float) -> void:
	for i in _marks.size():
		var age := _age[i]
		if age < 0.0:
			continue
		age += delta
		if age >= LIFE:
			_age[i] = -1.0
			_marks[i].visible = false
			_live -= 1
			continue
		_age[i] = age
		_mats[i].albedo_color.a = ALPHA * clampf((LIFE - age) / FADE, 0.0, 1.0)
	if _live <= 0:
		_live = 0
		set_process(false)


func _build() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2(SIZE, SIZE)
	var tex := _mark_texture()
	_age.resize(POOL)
	for i in POOL:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1, ALPHA)
		var mark := MeshInstance3D.new()
		mark.mesh = _quad
		mark.material_override = mat
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.visible = false
		add_child(mark)
		_marks.append(mark)
		_mats.append(mat)
		_age[i] = -1.0
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_mat.vertex_color_use_as_albedo = true
	var puff_mesh := QuadMesh.new()
	puff_mesh.size = Vector2(0.05, 0.05)
	puff_mesh.material = puff_mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.58, 0.52, 0.75))
	ramp.set_color(1, Color(0.62, 0.58, 0.52, 0.0))
	for i in PUFFS:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 6
		p.lifetime = PUFF_LIFE
		p.explosiveness = 1.0
		p.local_coords = false
		p.mesh = puff_mesh
		p.spread = 35.0
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.0
		p.gravity = Vector3(0, -2.5, 0)
		p.damping_min = 3.0
		p.damping_max = 5.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		p.color_ramp = ramp
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_puffs.append(p)


func _puff(pos: Vector3, n: Vector3) -> void:
	var p := _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	p.global_transform = Transform3D(Basis.IDENTITY, pos)
	p.direction = n
	p.restart()


## Dark centre, soft sooty rim, transparent edge.
static func _mark_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.32, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(0.02, 0.02, 0.02, 1.0),
		Color(0.06, 0.055, 0.05, 0.95),
		Color(0.14, 0.12, 0.1, 0.45),
		Color(0.2, 0.18, 0.15, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex
