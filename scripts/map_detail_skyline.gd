extends Node3D
## Detail op de Skyline (#322, stijl A-familie: hoge stadsdaken). Alles visueel: MultiMeshes zonder
## collider, dus geometrie, collision, bot-routes, spawns en NET_VERSION blijven zoals ze zijn.
##
## Wat er bij komt, in de kleuren van de stad en nooit in een teamkleur:
## - brandtrappen tegen de torens, met bordessen en leuningen;
## - watertanks op poten op de daken;
## - antennes en schoorsteentjes;
## - verlichte ramen in de diepte (emissie), zodat de straat leeft;
## - neonreclame in gedempt koper/roze, geen teamkleur.
const FIRE_Z := 3.0
const TANK_SPOTS := [Vector3(-27.0, 8.85, 34.0), Vector3(27.0, 8.85, -34.0), Vector3(0.0, 11.85, 25.5), Vector3(0.0, 11.85, -25.5)]
const ANT_SPOTS := [Vector3(27.0, 14.85, 30.0), Vector3(-27.0, 14.85, -30.0), Vector3(0.0, 11.85, 43.0), Vector3(0.0, 11.85, -43.0)]

const IRON := Color(0.2, 0.21, 0.22)
const TANK := Color(0.42, 0.44, 0.45)
const RUST := Color(0.36, 0.26, 0.2)
const GLASS_LIT := Color(1.0, 0.84, 0.55)
const NEON := Color(0.55, 0.26, 0.3) # gedempt, geen fel roze naast de teamkleuren

var steps: Array[Transform3D] = []
var rails: Array[Transform3D] = []
var tanks: Array[Transform3D] = []
var legs: Array[Transform3D] = []
var masts: Array[Transform3D] = []
var windows: Array[Transform3D] = []
var neon: Array[Transform3D] = []


func _ready() -> void:
	_fire_escapes()
	_tanks()
	_antennas()
	_lit_windows()
	_build()
	print("SkylineDetail: %d traptreden, %d leuningen, %d tanks, %d masten, %d ramen" % [
		steps.size(), rails.size(), tanks.size(), masts.size(), windows.size()])


## Brandtrappen tegen de twee torens: een rij treden omhoog plus een leuning per verdieping.
func _fire_escapes() -> void:
	for pair in [[-1.0, 1.0], [1.0, -1.0]]:
		var side: float = pair[0]
		var x := side * 6.4
		var z := -12.0
		while z <= 12.0:
			steps.append(Transform3D(Basis.from_scale(Vector3(1.4, 0.08, 0.9)), Vector3(x, 4.0, z)))
			z += FIRE_Z
		for h in [4.0, 7.0, 10.0]:
			rails.append(Transform3D(Basis.from_scale(Vector3(0.06, 1.0, 24.0)), Vector3(x + side * 0.7, h + 0.5, 0.0)))


## Watertanks op poten op vier daken (dezelfde plekken als de daken in de map).
func _tanks() -> void:
	for spot in TANK_SPOTS:
		var at: Vector3 = spot
		tanks.append(Transform3D(Basis.from_scale(Vector3(2.2, 2.6, 2.2)), at + Vector3.UP * 1.4))
		for i in 4:
			var dx := -0.7 if i % 2 == 0 else 0.7
			var dz := -0.7 if i < 2 else 0.7
			legs.append(Transform3D(Basis.from_scale(Vector3(0.12, 1.4, 0.12)), at + Vector3(dx, 0.7, dz)))


## Antennes en schoorsteentjes op de hoogste daken.
func _antennas() -> void:
	for spot in ANT_SPOTS:
		var at: Vector3 = spot
		masts.append(Transform3D(Basis.from_scale(Vector3(0.09, 4.5, 0.09)), at + Vector3.UP * 2.25))
		masts.append(Transform3D(Basis.from_scale(Vector3(1.4, 0.06, 0.06)), at + Vector3.UP * 3.4))
		masts.append(Transform3D(Basis.from_scale(Vector3(0.9, 0.06, 0.06)), at + Vector3.UP * 2.8))


## Verlichte ramen in de diepte: twee rijen per torenwand, deterministisch aan of uit.
func _lit_windows() -> void:
	for block in [[Vector3(-27.0, 0.0, 0.0), 12.0], [Vector3(27.0, 0.0, 0.0), 12.0]]:
		var base: Vector3 = block[0]
		var span: float = block[1]
		for row in 3:
			for col in 4:
				var at := Vector3(base.x + (-span * 0.5 + 2.0 + float(col) * 3.0), 1.6 + float(row) * 1.5, base.z)
				var lit := (int(absf(at.x) * 31.0) + row * 7 + col * 3) % 10 < 5
				if not lit:
					continue
				windows.append(Transform3D(Basis.from_scale(Vector3(1.1, 1.0, 0.06)), at))
	# neonreclame: drie panelen in de straat, gedempt roze
	for at in [Vector3(-8.0, 3.4, 8.0), Vector3(9.0, 4.2, -7.0), Vector3(0.0, 5.0, 16.0)]:
		neon.append(Transform3D(Basis.from_scale(Vector3(2.4, 1.1, 0.08)), at))


func _build() -> void:
	_add_boxes(steps, IRON, "FireSteps")
	_add_boxes(rails, IRON, "FireRails")
	_add_boxes(legs, IRON, "TankLegs")
	_add_boxes(masts, RUST, "Masts")
	if not tanks.is_empty():
		var mmi := _multimesh(tanks, "WaterTanks")
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 12
		cyl.rings = 1
		mmi.multimesh.mesh = cyl
		mmi.material_override = _solid(TANK, 0.55, 0.2)
		add_child(mmi)
	if not windows.is_empty():
		var glow := StandardMaterial3D.new()
		glow.albedo_color = GLASS_LIT
		glow.emission_enabled = true
		glow.emission = GLASS_LIT
		glow.emission_energy_multiplier = 1.8
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mmw := _multimesh(windows, "LitWindows")
		mmw.multimesh.mesh = BoxMesh.new()
		mmw.material_override = glow
		add_child(mmw)
	if not neon.is_empty():
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = NEON
		nmat.emission_enabled = true
		nmat.emission = NEON
		nmat.emission_energy_multiplier = 1.4
		nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mmn := _multimesh(neon, "Neon")
		mmn.multimesh.mesh = BoxMesh.new()
		mmn.material_override = nmat
		add_child(mmn)


func _add_boxes(xforms: Array[Transform3D], col: Color, node_name: String) -> void:
	if xforms.is_empty():
		return
	var mmi := _multimesh(xforms, node_name)
	mmi.multimesh.mesh = BoxMesh.new()
	mmi.material_override = _solid(col, 0.7, 0.2)
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
