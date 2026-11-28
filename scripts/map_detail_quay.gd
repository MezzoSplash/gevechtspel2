extends Node3D
## Haven-detail voor Quay (#322, stijl A-familie). Alles visueel: MultiMeshes zonder collider, dus
## geometrie, collision, bot-routes, spawns en NET_VERSION blijven zoals ze zijn.
##
## Wat er bij komt, in de kleuren van de haven en nooit in een teamkleur:
## - bolders langs de kade (donker gietijzer);
## - fenders (hangende rubberbanden) tegen de kademuur, aan de waterkant;
## - trossen als dunne lijnen van bolder naar water;
## - houten pallets en kisten op de kade (gedempt hout, geen oranje);
## - teamkleur-band op de kadezijde van elke spawn, als accent bij de teamwand.
const BOLLARD_R := 0.28
const BOLLARD_H := 0.75
const BOLLARD_Z := 7.0
const BOLLARD_Z_FROM := -34.0
const BOLLARD_Z_TO := 34.0
const KADE_X := 18.6
const FENDER_Z := 4.5
const PALET_Z := 22.0
const PALET_X := 27.0

const IRON := Color(0.22, 0.23, 0.24)
const RUBBER := Color(0.13, 0.13, 0.14)
const ROPE := Color(0.42, 0.36, 0.28)
const WOOD := Color(0.42, 0.33, 0.24)
const TEAM_BLUE := Color(0.27, 0.46, 0.62)
const TEAM_ORANGE := Color(0.7, 0.44, 0.18)

var bollards: Array[Transform3D] = []
var fenders: Array[Transform3D] = []
var ropes: Array[Transform3D] = []
var pallets: Array[Transform3D] = []
var crates: Array[Transform3D] = []
var rail_blue: Array[Transform3D] = []
var rail_orange: Array[Transform3D] = []


func _ready() -> void:
	_kade_props()
	_spawn_accents()
	_build()
	print("QuayDetail: %d bolders, %d fenders, %d trossen, %d pallets, %d kisten" % [
		bollards.size(), fenders.size(), ropes.size(), pallets.size(), crates.size()])


## Bolders, fenders en trossen langs beide kades; pallets en kisten erachter.
func _kade_props() -> void:
	var z := BOLLARD_Z_FROM
	while z <= BOLLARD_Z_TO:
		for side in [-1.0, 1.0]:
			var at := Vector3(side * KADE_X, BOLLARD_H * 0.5, z)
			bollards.append(Transform3D(Basis.from_scale(Vector3(BOLLARD_R * 2.0, BOLLARD_H, BOLLARD_R * 2.0)), at))
			# Een korte tros van de bolder naar het water toe.
			var r_at := at + Vector3(-side * 0.9, -0.35, 0.2)
			ropes.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.06, 1.9)), r_at))
		z += BOLLARD_Z
	# Fenders hangen aan de kant van het water, iets onder de kaderand.
	var fz := -32.0
	while fz <= 32.0:
		for side in [-1.0, 1.0]:
			fenders.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.8, 0.5)), Vector3(side * (KADE_X - 1.2), 1.1, fz)))
		fz += FENDER_Z
	# Pallets en kisten op de kade, tussen de bolders.
	var pz := -30.0
	while pz <= 30.0:
		for side in [-1.0, 1.0]:
			var base := Vector3(side * PALET_X, 0.09, pz)
			pallets.append(Transform3D(Basis.from_scale(Vector3(1.2, 0.18, 1.0)), base))
			if int(absf(pz)) % 3 == 0:
				crates.append(Transform3D(Basis.from_scale(Vector3(0.9, 0.9, 0.9)), base + Vector3(0, 0.54, 0)))
		pz += PALET_Z


## Teamkleur als accent op de kadezijde van elke spawn: blauw zuid, oranje noord.
func _spawn_accents() -> void:
	for n in get_parent().get_children():
		if not (n is CSGBox3D):
			continue
		var nm := String(n.name).to_lower()
		if not (nm.begins_with("wallnorth") or nm.begins_with("wallsouth") or nm.begins_with("spawnwall")):
			continue
		var box := n as CSGBox3D
		var sz := box.size
		var band := Vector3(sz.x * 0.6, 0.12, 0.12) if sz.x > sz.z else Vector3(0.12, 0.12, sz.z * 0.6)
		var at := box.global_position + Vector3.UP * (sz.y * 0.5 + 0.1)
		var xf := Transform3D(Basis.from_scale(band), at)
		if at.z > 0.0:
			rail_blue.append(xf)
		else:
			rail_orange.append(xf)


func _build() -> void:
	if not bollards.is_empty():
		var mmi := _multimesh(bollards, "Bollards")
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 8
		cyl.rings = 1
		mmi.multimesh.mesh = cyl
		mmi.material_override = _solid(IRON, 0.55, 0.4)
		add_child(mmi)
	_add_boxes(fenders, RUBBER, "Fenders")
	_add_boxes(pallets, WOOD, "Pallets")
	_add_boxes(crates, WOOD.darkened(0.15), "Crates")
	_add_boxes(rail_blue, TEAM_BLUE, "RailBlue")
	_add_boxes(rail_orange, TEAM_ORANGE, "RailOrange")
	if not ropes.is_empty():
		var mmr := _multimesh(ropes, "Ropes")
		var link := CylinderMesh.new()
		link.radial_segments = 5
		link.rings = 1
		mmr.multimesh.mesh = link
		mmr.material_override = _solid(ROPE, 0.9, 0.0)
		add_child(mmr)


func _add_boxes(xforms: Array[Transform3D], col: Color, node_name: String) -> void:
	if xforms.is_empty():
		return
	var mmi := _multimesh(xforms, node_name)
	mmi.multimesh.mesh = BoxMesh.new()
	mmi.material_override = _solid(col, 0.8, 0.05)
	add_child(mmi)


func _multimesh(xforms: Array[Transform3D], node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mmi


func _solid(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
