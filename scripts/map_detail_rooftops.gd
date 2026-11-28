extends Node3D
## Detail op de Rooftops (#322, stijl A-familie: daken in de stad). Alles visueel: MultiMeshes zonder
## collider, dus geometrie, collision, bot-routes, spawns en NET_VERSION blijven zoals ze zijn.
##
## Wat er bij komt:
## - teamkleur op de dakranden: de zuidkant blauw, de noordkant oranje, bovenop de bestaande parapetten;
## - dakkapellen met glas op de schilden, met een kozijn;
## - schoorstenen met potten langs de dakrand;
## - watertanks op poten op de zijdekken;
## - ventilatorroosters op de bestaande airco-units;
## - antennemasten op de schilden.
const SKY_GLASS := Color(0.16, 0.2, 0.26)
const FRAME := Color(0.2, 0.19, 0.18)
const BRICK := Color(0.3, 0.29, 0.28) # grijze klei: geen zalm die als team-Oranje kan lezen
const POT := Color(0.2, 0.2, 0.2) # donkere klei: geen zalm dat als team-Oranje leest
const TANK := Color(0.42, 0.44, 0.45) # gegalvaniseerd grijs: geen crème dat onder de warme zon als zalm leest
const STEEL := Color(0.34, 0.35, 0.36) # donker staal: geen crème vlakken die als team-Oranje lezen
const TEAM_BLUE := Color(0.27, 0.46, 0.62)
const TEAM_ORANGE := Color(0.7, 0.44, 0.18)

var rail_blue: Array[Transform3D] = []
var rail_orange: Array[Transform3D] = []
var panes: Array[Transform3D] = []
var pane_frames: Array[Transform3D] = []
var chimneys: Array[Transform3D] = []
var pots: Array[Transform3D] = []
var tank_shells: Array[Transform3D] = []
var tank_legs: Array[Transform3D] = []
var fans: Array[Transform3D] = []
var masts: Array[Transform3D] = []


func _ready() -> void:
	_parapet_colours()
	_skylights()
	_chimneys()
	_water_tanks()
	_fans()
	_antennas()
	_build()
	print("RooftopsDetail: %d dakranden, %d dakkapellen, %d schoorstenen, %d tanks, %d ventilatoren, %d masten" % [
		rail_blue.size() + rail_orange.size(), panes.size(), chimneys.size(), tank_shells.size(), fans.size(), masts.size()])


func _node(node_name: String) -> CSGBox3D:
	var n := get_parent().get_node_or_null(node_name)
	return n as CSGBox3D


## Teamkleur als band bovenop elk parapet: zuid (z > 0) blauw, noord oranje.
func _parapet_colours() -> void:
	for n in get_parent().get_children():
		if not (n is CSGBox3D):
			continue
		var nm := String(n.name)
		if not nm.begins_with("SouthPar") and not nm.begins_with("NorthPar"):
			continue
		var box := n as CSGBox3D
		var sz := box.size
		# Het parapet is 0,5 dik; de band volgt de lange kant.
		var long_x := sz.x >= sz.z
		var band := Vector3(sz.x + 0.06, 0.1, 0.1) if long_x else Vector3(0.1, 0.1, sz.z + 0.06)
		var at := box.global_position + Vector3.UP * (sz.y * 0.5 + 0.05)
		var xf := Transform3D(Basis.from_scale(band), at)
		if at.z > 0.0:
			rail_blue.append(xf)
		else:
			rail_orange.append(xf)


## Dakkapellen op het dak van de schilden (SouthShell/NorthShell, bovenkant op y = 6).
func _skylights() -> void:
	for shell_name in ["SouthShell", "NorthShell"]:
		var shell := _node(shell_name)
		if shell == null:
			continue
		var sz := shell.size
		var top := shell.global_position.y + sz.y * 0.5
		var cols := 3
		var rows := 2
		for c in cols:
			for r in rows:
				var x := -sz.x * 0.3 + float(c) * (sz.x * 0.3)
				var z := shell.global_position.z - sz.z * 0.22 + float(r) * (sz.z * 0.44)
				var at := Vector3(x, top + 0.04, z)
				var basis := Basis(Vector3.RIGHT, -PI * 0.5) # vlak op het dak
				pane_frames.append(Transform3D(basis.scaled(Vector3(2.0, 2.6, 1.0)), at))
				panes.append(Transform3D(basis.scaled(Vector3(1.7, 2.3, 1.0)), at + Vector3.UP * 0.02))


## Schoorstenen met potten langs de dakranden van de schilden.
func _chimneys() -> void:
	for shell_name in ["SouthShell", "NorthShell"]:
		var shell := _node(shell_name)
		if shell == null:
			continue
		var sz := shell.size
		var top := shell.global_position.y + sz.y * 0.5
		for i in 3:
			var x := shell.global_position.x - sz.x * 0.36 + float(i) * (sz.x * 0.36)
			var z := shell.global_position.z + (sz.z * 0.42 if shell.global_position.z > 0.0 else -sz.z * 0.42)
			var h := 2.2
			chimneys.append(Transform3D(Basis.from_scale(Vector3(1.1, h, 1.1)), Vector3(x, top + h * 0.5, z)))
			for p in 2:
				pots.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.5, 0.3)), Vector3(x - 0.25 + float(p) * 0.5, top + h + 0.25, z)))


## Watertanks op poten op de twee zijdekken (WestDeck op z 24, EastDeck op z -24).
func _water_tanks() -> void:
	for deck_name in ["WestDeck", "EastDeck"]:
		var deck := _node(deck_name)
		if deck == null:
			continue
		var at := deck.global_position + Vector3.UP * (deck.size.y * 0.5)
		var centre := at + Vector3.UP * (2.4 + 0.9)
		tank_shells.append(Transform3D(Basis.from_scale(Vector3(2.2, 2.4, 2.2)), centre))
		for i in 4:
			var dx := -0.8 if i % 2 == 0 else 0.8
			var dz := -0.8 if i < 2 else 0.8
			tank_legs.append(Transform3D(Basis.from_scale(Vector3(0.14, 2.4, 0.14)), at + Vector3(dx, 1.2, dz)))


## Ventilatoren bovenop de bestaande airco-units.
func _fans() -> void:
	for n in get_parent().get_children():
		if not (n is CSGBox3D):
			continue
		if not String(n.name).contains("AC"):
			continue
		var box := n as CSGBox3D
		var at := box.global_position + Vector3.UP * (box.size.y * 0.5 + 0.05)
		fans.append(Transform3D(Basis.from_scale(Vector3(1.5, 0.08, 1.5)), at))


## Antennes op de schilden: een mast met twee dwarsspijlen.
func _antennas() -> void:
	for shell_name in ["SouthShell", "NorthShell"]:
		var shell := _node(shell_name)
		if shell == null:
			continue
		var sz := shell.size
		var top := shell.global_position.y + sz.y * 0.5
		var x := shell.global_position.x + sz.x * 0.42
		var z := shell.global_position.z
		masts.append(Transform3D(Basis.from_scale(Vector3(0.1, 5.0, 0.1)), Vector3(x, top + 2.5, z)))
		masts.append(Transform3D(Basis.from_scale(Vector3(1.6, 0.07, 0.07)), Vector3(x, top + 4.2, z)))
		masts.append(Transform3D(Basis.from_scale(Vector3(1.1, 0.07, 0.07)), Vector3(x, top + 3.6, z)))


func _build() -> void:
	_add_boxes(rail_blue, TEAM_BLUE, "RailBlue")
	_add_boxes(rail_orange, TEAM_ORANGE, "RailOrange")
	_add_boxes(chimneys, BRICK, "Chimneys")
	_add_boxes(pots, POT, "ChimneyPots")
	_add_boxes(tank_legs, STEEL, "TankLegs")
	_add_boxes(fans, STEEL, "Fans")
	_add_boxes(masts, STEEL, "Masts")
	if not tank_shells.is_empty():
		var mmi := _multimesh(tank_shells, "WaterTanks")
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 12
		cyl.rings = 1
		mmi.multimesh.mesh = cyl
		mmi.material_override = _solid(TANK, 0.55, 0.2)
		add_child(mmi)
	_add_quads(pane_frames, [FRAME], false, "SkylightFrames")
	_add_quads(panes, [SKY_GLASS], true, "SkylightGlass")


func _add_quads(xforms: Array[Transform3D], colors: Array[Color], unshaded: bool, node_name: String) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = colors[0]
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_boxes(xforms: Array[Transform3D], col: Color, node_name: String) -> void:
	if xforms.is_empty():
		return
	var mmi := _multimesh(xforms, node_name)
	mmi.multimesh.mesh = BoxMesh.new()
	mmi.material_override = _solid(col, 0.7, 0.1)
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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _solid(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
