class_name GrappleRope
extends Node3D
## The grapple's rope: a thin glowing crystal beam from the left hand to the anchor, and a spark on
## the anchor. Visual only, top-level (world space), owned by the pawn. Every machine draws it from the
## pawn's synced `grappling` / `grapple_at`, the owner from its own state.

const WIDTH := 0.035
const SPARK := 0.16
const COLOR := Color(0.72, 0.92, 1.0) # ice: the UI crystal's "ready / moving" colour

var _beam: MeshInstance3D
var _spark: MeshInstance3D
var _mat: StandardMaterial3D


static func ensure(parent: Node3D) -> GrappleRope:
	var r := parent.get_node_or_null("GrappleRope") as GrappleRope
	if r == null:
		r = GrappleRope.new()
		r.name = "GrappleRope"
		parent.add_child(r)
	return r


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = COLOR
	_mat.emission_enabled = true
	_mat.emission = COLOR
	_mat.emission_energy_multiplier = 2.0
	_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	_beam.mesh = box
	_beam.material_override = _mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_spark = MeshInstance3D.new()
	_spark.mesh = CrystalMesh.part(&"spark")
	_spark.material_override = _mat
	_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spark)
	visible = false


## Draw the rope from `from` to `to`, or hide it.
func show_line(on: bool, from: Vector3, to: Vector3) -> void:
	if _beam == null:
		return
	var d := to - from
	if not on or d.length_squared() < 1e-4:
		visible = false
		return
	visible = true
	var l := d.length()
	var z := d / l
	var ref := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	var y := z.cross(x)
	_beam.global_transform = Transform3D(Basis(x * WIDTH, y * WIDTH, z * l), from + d * 0.5)
	_spark.global_transform = Transform3D(Basis().scaled(Vector3.ONE * SPARK / 0.06), to)
