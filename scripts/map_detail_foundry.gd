extends Node3D
## Detail op de Foundry (#322, stijl A-familie: gieterij). Alles visueel: MultiMeshes zonder collider,
## dus geometrie, collision, bot-routes, spawns en NET_VERSION blijven zoals ze zijn.
##
## Wat er bij komt:
## - leidingen langs de vier wanden met ventielen, zoals in een echte gieterij;
## - kettingen die uit de hijskranen hangen;
## - gloeiende randen bij de oven en de lepels (heet metaal, alleen emissie);
## - gevaarstrepen op de vloer bij de gietlijn;
## - teamkleur-accenten op de mezzanine-leuningen, zodat je aan de rail ziet welke kant je op kijkt.
const PIPE_Y := [3.2, 6.8]
const PIPE_R := 0.16
const VALVE_EVERY := 9.0
const WALL_IN := 0.6
const CHAIN_EVERY := 6.0
const CHAIN_LEN := 2.4
const CHAIN_R := 0.05
const HAZARD_Z := [-7.6, -6.8, 6.8, 7.6]
const HAZARD_X := 30.0

const IRON := Color(0.44, 0.42, 0.4)
const RUST := Color(0.6, 0.36, 0.26)
const HAZARD := Color(0.86, 0.68, 0.16)
const HOT := Color(1.0, 0.55, 0.2)
const TEAM_BLUE := Color(0.27, 0.46, 0.62)
const TEAM_ORANGE := Color(0.7, 0.44, 0.18)

var pipes: Array[Transform3D] = []
var valves: Array[Transform3D] = []
var chains: Array[Transform3D] = []
var hot: Array[Transform3D] = []
var hazard: Array[Transform3D] = []
var rail_blue: Array[Transform3D] = []
var rail_orange: Array[Transform3D] = []


func _ready() -> void:
	_wall_pipes()
	_crane_chains()
	_hot_spots()
	_floor_stripes()
	_rail_accents()
	_build()
	print("FoundryDetail: %d leidingen, %d ventielen, %d kettingen, %d gloeiende randen, %d strepen" % [
		pipes.size(), valves.size(), chains.size(), hot.size(), hazard.size()])


## Twee leidingruns langs elke wand, met een ventiel om de paar meter.
func _wall_pipes() -> void:
	var walls := {
		"west": [-31.9, 0.0, -48.0, 48.0, true],
		"east": [31.9, 0.0, -48.0, 48.0, true],
		"north": [0.0, -47.9, -32.0, 32.0, false],
		"south": [0.0, 47.9, -32.0, 32.0, false],
	}
	for key in walls:
		var w: Array = walls[key]
		var along_z: bool = w[4]
		for y in PIPE_Y:
			var pos_a: Vector3 = Vector3(w[0], y, w[2]) if along_z else Vector3(w[2], y, w[1])
			var pos_b: Vector3 = Vector3(w[0], y, w[3]) if along_z else Vector3(w[3], y, w[1])
			var centre := (pos_a + pos_b) * 0.5
			var span := (pos_b - pos_a).length()
			var axis := (pos_b - pos_a).normalized()
			# Een cilinder staat standaard langs Y; draai hem naar de looprichting.
			var basis := Basis()
			if along_z:
				basis = Basis(Vector3.RIGHT, PI * 0.5) # Y -> Z
			else:
				basis = Basis(Vector3.BACK, PI * 0.5) # Y -> X
			basis = Basis(axis.normalized(), 0.0) * basis if false else basis
			pipes.append(Transform3D(basis.scaled(Vector3(PIPE_R, span * 0.5, PIPE_R)), centre))
			# Een tweede, dunnere leiding eronder voor de stoom.
			var y2: float = y - 0.45
			var centre2 := Vector3(centre.x, y2, centre.z)
			pipes.append(Transform3D(basis.scaled(Vector3(PIPE_R * 0.6, span * 0.5, PIPE_R * 0.6)), centre2))
			# Ventielen: een ring om de leiding, om de 9 m.
			var t := -span * 0.5 + VALVE_EVERY
			while t < span * 0.5:
				var at := centre + axis * t
				valves.append(Transform3D(Basis(Vector3.UP, PI * 0.5), at))
				t += VALVE_EVERY


## Kettingen uit de twee hijskranen (CraneA op z 20, CraneB op z -20, balk y 11.4).
func _crane_chains() -> void:
	for z in [20.0, -20.0]:
		var x := -24.0
		while x <= 24.0:
			# Niet midden in de doorloop van de hal.
			if absf(x) > 10.0 or absf(z) < 15.0:
				chains.append(Transform3D(Basis(Vector3.ONE * CHAIN_R, Vector3.UP * CHAIN_LEN, Vector3.ONE * CHAIN_R), Vector3(x, 11.0 - CHAIN_LEN * 0.5, z)))
			x += CHAIN_EVERY


## Heet metaal: de tap van de oven en de randen van de lepels.
func _hot_spots() -> void:
	hot.append(Transform3D(Basis(Vector3(1.2, 0.12, 1.4), Vector3.UP, Vector3(1.2, 0.12, 1.4)), Vector3(0, 0.95, 3.1)))
	for at in [Vector3(8, 6.9, 20), Vector3(-8, 6.9, -20), Vector3(6.5, 1.4, 19.6), Vector3(-6.5, 1.4, -19.6)]:
		hot.append(Transform3D(Basis(Vector3(1.5, 0.1, 1.5), Vector3.UP, Vector3(1.5, 0.1, 1.5)), at))


## Gevaarstrepen op de vloer langs de gietlijn.
func _floor_stripes() -> void:
	for z in HAZARD_Z:
		hazard.append(Transform3D(Basis(Vector3(HAZARD_X * 2.0, 0.012, 0.14), Vector3.UP, Vector3(HAZARD_X * 2.0, 0.012, 0.14)), Vector3(0, 0.03, z)))


## Teamkleur op de mezzanine-leuningen: _B blauw, _O oranje.
func _rail_accents() -> void:
	for n in get_parent().get_children():
		if not (n is CSGBox3D):
			continue
		var nm := String(n.name).to_lower()
		if not nm.begins_with("mezzrail"):
			continue
		var box := n as CSGBox3D
		var sz := box.size
		var basis := Basis(Vector3(sz.x, 0.14, sz.z), Vector3.UP, Vector3(sz.x, 0.14, sz.z))
		var at := box.global_position + Vector3.UP * (sz.y * 0.5 + 0.08)
		var xf := Transform3D(basis, at)
		if nm.ends_with("_b"):
			rail_blue.append(xf)
		elif nm.ends_with("_o"):
			rail_orange.append(xf)


func _build() -> void:
	if not pipes.is_empty():
		var mmi := _multimesh(pipes, "Pipes")
		# Laag-poly: een leiding is een silhouet, geen model. Standaard is 64 segmenten, dat is 8x te veel.
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 8
		cyl.rings = 1
		mmi.multimesh.mesh = cyl
		mmi.material_override = _solid(IRON, 0.55, 0.35)
		add_child(mmi)
	if not valves.is_empty():
		var mmv := _multimesh(valves, "Valves")
		# Een ventiel is op deze afstand een kraag om de leiding, geen torus: 68 torussen kostten
		# 17k primitives, deze dozen 800.
		var collar := BoxMesh.new()
		collar.size = Vector3(PIPE_R * 3.2, PIPE_R * 2.2, PIPE_R * 3.2)
		mmv.multimesh.mesh = collar
		mmv.material_override = _solid(RUST, 0.7, 0.2)
		add_child(mmv)
	if not chains.is_empty():
		var mmc := _multimesh(chains, "Chains")
		var link := CylinderMesh.new()
		link.radial_segments = 6
		link.rings = 1
		mmc.multimesh.mesh = link
		mmc.material_override = _solid(IRON, 0.5, 0.5)
		add_child(mmc)
	if not hazard.is_empty():
		var mmh := _multimesh(hazard, "Hazard")
		mmh.multimesh.mesh = BoxMesh.new()
		mmh.material_override = _solid(HAZARD, 0.7, 0.0)
		add_child(mmh)
	for pair in [[rail_blue, TEAM_BLUE, "RailBlue"], [rail_orange, TEAM_ORANGE, "RailOrange"]]:
		var arr: Array = pair[0]
		if arr.is_empty():
			continue
		var mmr := _multimesh(arr, String(pair[2]))
		mmr.multimesh.mesh = BoxMesh.new()
		mmr.material_override = _solid(pair[1], 0.55, 0.0)
		add_child(mmr)
	if not hot.is_empty():
		# Heet metaal licht zelf: emissie, geen lichtbron (dat kost te veel).
		var glow := StandardMaterial3D.new()
		glow.albedo_color = HOT
		glow.emission_enabled = true
		glow.emission = HOT
		glow.emission_energy_multiplier = 2.2
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mmg := _multimesh(hot, "HotMetal")
		mmg.multimesh.mesh = BoxMesh.new()
		mmg.material_override = glow
		add_child(mmg)


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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _solid(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
