class_name CrystalMesh
extends RefCounted
## Procedural faceted meshes for the B1 crystal body (#164 facelift). No assets: every part is a
## low-segment "ring stack" along +Y with flat (per-face) normals, so it reads as cut crystal.
## A ring is [y, radius_x, radius_z]; a radius of 0 makes an apex. Shapes must be convex.

static var _cache := {}


## Flat-shaded mesh through `rings` with `sides` facets around the axis (twisted by `twist` rad).
static func ring_stack(rings: Array, sides: int, twist := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid_y := (float(rings[0][0]) + float(rings[-1][0])) * 0.5
	var pts: Array = []
	for r in rings:
		var ring: Array[Vector3] = []
		for s in sides:
			var a := TAU * s / sides + twist
			ring.append(Vector3(cos(a) * float(r[1]), float(r[0]), sin(a) * float(r[2])))
		pts.append(ring)
	var centre := Vector3(0, mid_y, 0)
	for i in rings.size() - 1:
		for s in sides:
			var n := (s + 1) % sides
			_quad(st, pts[i][s], pts[i][n], pts[i + 1][n], pts[i + 1][s], centre)
	for cap in [0, rings.size() - 1]:
		if float(rings[cap][1]) > 0.0:
			var c := Vector3(0, float(rings[cap][0]), 0)
			for s in sides:
				_tri(st, c, pts[cap][s], pts[cap][(s + 1) % sides], centre)
	return st.commit()


## Cached shapes of the body parts, shared by every pawn.
static func part(id: StringName) -> ArrayMesh:
	if not _cache.has(id):
		_cache[id] = _build(id)
	return _cache[id]


static func _build(id: StringName) -> ArrayMesh:
	match id:
		&"torso": # shoulders wide, waist narrow; 0.74 m tall, centred
			return ring_stack([[-0.36, 0.10, 0.08], [-0.22, 0.15, 0.11], [0.02, 0.19, 0.13],
				[0.24, 0.25, 0.15], [0.33, 0.20, 0.12], [0.38, 0.08, 0.06]], 6, PI / 6)
		&"pelvis": # floating hip shard under the waist seam
			return ring_stack([[-0.11, 0.0, 0.0], [-0.03, 0.12, 0.08], [0.04, 0.15, 0.10], [0.08, 0.09, 0.07]], 6, PI / 6)
		&"chest": # pale plate on the front of the chest
			return ring_stack([[-0.14, 0.0, 0.0], [-0.02, 0.13, 0.05], [0.10, 0.15, 0.05], [0.16, 0.0, 0.0]], 4, PI / 4)
		&"shoulder":
			return ring_stack([[-0.07, 0.0, 0.0], [0.0, 0.08, 0.08], [0.05, 0.06, 0.06], [0.08, 0.0, 0.0]], 5)
		&"head": # angular helmet-like shard
			return ring_stack([[-0.14, 0.04, 0.04], [-0.05, 0.12, 0.13], [0.07, 0.11, 0.12], [0.17, 0.0, 0.0]], 5, PI / 2)
		&"visor":
			return ring_stack([[-0.025, 0.11, 0.02], [0.025, 0.10, 0.02]], 4, PI / 4)
		&"hand":
			return ring_stack([[-0.06, 0.0, 0.0], [-0.01, 0.055, 0.045], [0.04, 0.05, 0.04], [0.07, 0.0, 0.0]], 4, PI / 4)
		&"foot": # along +Y; the pose turns it to point forward
			return ring_stack([[-0.12, 0.0, 0.0], [-0.06, 0.06, 0.045], [0.08, 0.065, 0.05], [0.14, 0.0, 0.0]], 4, PI / 4)
		&"seam": # flat glowing ring between parts
			return ring_stack([[-0.012, 0.12, 0.09], [0.012, 0.12, 0.09]], 6, PI / 6)
		&"limb": # unit segment along +Y, base at y=0; the pose scales Y to the bone length
			return ring_stack([[0.0, 0.065, 0.065], [0.4, 0.058, 0.058], [0.75, 0.048, 0.048], [1.0, 0.036, 0.036]], 5)
		&"limb_leg": # same, heavier: the legs have to read at 20 m
			return ring_stack([[0.0, 0.088, 0.088], [0.45, 0.080, 0.080], [0.8, 0.066, 0.066], [1.0, 0.052, 0.052]], 5)
		&"spark": # small floating glow shard (ankles, wrists)
			return ring_stack([[-0.04, 0.0, 0.0], [0.0, 0.025, 0.025], [0.04, 0.0, 0.0]], 4)
	return ring_stack([[-0.05, 0.0, 0.0], [0.0, 0.05, 0.05], [0.05, 0.0, 0.0]], 4)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3) -> void:
	_tri(st, a, b, c, centre)
	_tri(st, a, c, d, centre)


## One outward-facing triangle (Godot: clockwise front faces) with its own flat normal.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - centre) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(b)


## Pale crystal shell (head, hands, feet, chest plate).
static func shell_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.89, 0.94)
	m.roughness = 0.35
	m.metallic = 0.15
	return m


## Glowing seam in a team colour (unshaded so it reads in shadow too).
static func glow_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.lightened(0.15)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	return m
