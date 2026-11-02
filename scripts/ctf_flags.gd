class_name CtfFlags
extends Node3D
## #160: the two CTF flags in the world, on every machine. Pure visuals: follows Game.flags (base, on
## the ground, or above its carrier). A ring marks each base. Child of Game, made by CtfFlags.ensure().

const POLE_H := 2.4
const CARRY_OFFSET := Vector3(0, 0.6, 0) # above the carrier's origin, so the cloth shows over the head

var _flags: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []


## Make the node under Game if CTF runs and it is missing; drop it otherwise.
static func ensure(g: Node) -> void:
	var n := g.get_node_or_null("CtfFlags")
	if g.is_ctf() and n == null:
		var f := CtfFlags.new()
		f.name = "CtfFlags"
		g.add_child(f)
	elif not g.is_ctf() and n != null:
		n.queue_free()


func _ready() -> void:
	for t in 2:
		var col := Player.team_color(t)
		var flag := Node3D.new()
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.04
		pm.bottom_radius = 0.04
		pm.height = POLE_H
		pole.mesh = pm
		pole.position.y = POLE_H * 0.5
		pole.material_override = _mat(Color(0.85, 0.86, 0.88))
		flag.add_child(pole)
		var cloth := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.9, 0.55, 0.04)
		cloth.mesh = cm
		cloth.position = Vector3(0.47, POLE_H - 0.32, 0)
		cloth.material_override = _mat(col)
		flag.add_child(cloth)
		add_child(flag)
		_flags.append(flag)
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = Objective.TOUCH_RADIUS - 0.12
		rm.outer_radius = Objective.TOUCH_RADIUS
		ring.mesh = rm
		ring.material_override = _mat(col.darkened(0.2))
		add_child(ring)
		_rings.append(ring)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _process(delta: float) -> void:
	if Game.flags.size() != 2:
		visible = false
		return
	visible = true
	for t in 2:
		var f: Dictionary = Game.flags[t]
		_rings[t].global_position = (f.home as Vector3) + Vector3(0, 0.05, 0)
		var at := CTF.flag_world_pos(Game, t)
		if int(f.state) == Objective.CARRIED:
			at += CARRY_OFFSET
		_flags[t].global_position = at
		_flags[t].rotation.y += 0.0 if int(f.state) == Objective.CARRIED else delta * 0.6
