extends Node3D
## Detail op de Townhouses-gevels dat niet van een stijlkeuze afhangt (#322): ramen, dakranden en
## kadeverlichting. Alles wordt één keer bij het starten opgebouwd en in MultiMeshes gezet, zodat het
## per soort één draw call kost.
##
## Regels:
## - Ramen komen alleen op gevelvlakken die vrij naar buiten kijken (een ray vanaf het vlak raakt niets).
##   Zo staan ze niet in een muur die tegen een andere muur ligt.
## - Dakranden volgen dezelfde vlakken: een donkere band langs de bovenkant, zodat de overgang van gevel
##   naar dak leesbaar is.
## - De kade krijgt lantaarnpalen; die geven schaal aan de ruimte. Geen echte lichtbronnen (te duur met
##   twaalf stuks) - alleen een lichtend kopje.
const WIN := Vector2(0.85, 1.15)
const FRAME_SCALE := Vector2(1.16, 1.12)
const WIN_GAP_X := 2.8
const WIN_GAP_Y := 3.2
const WIN_FIRST_Y := 3.2
const EXPOSE_NEAR := 0.35
const EXPOSE_FAR := 2.2
const TRIM_H := 0.35
const TRIM_D := 0.5
const LAMP_X := 5.6
const LAMP_Z := 12.0
const LAMP_Z_FROM := -36.0
const LAMP_Z_TO := 37.0
const LAMP_H := 3.6

var _frames: Array[Transform3D] = []
var _glass: Array[Transform3D] = []
var _tones: Array[Color] = []
var _trim: Array[Transform3D] = []
var _lamp_poles: Array[Transform3D] = []
var _lamp_heads: Array[Transform3D] = []


func _ready() -> void:
	var solids := _solid_boxes()
	var boxes := _faced_boxes()
	for box in boxes:
		for face in _faces(box):
			if not _exposed(solids, box, face):
				continue
			_windows_on(box, face)
			_trim_on(box, face)
	_build()
	print("MapDetail: %d ramen, %d dakranden, %d lantaarns" % [_glass.size(), _trim.size(), _lamp_heads.size()])


func _faced_boxes() -> Array[CSGBox3D]:
	var out: Array[CSGBox3D] = []
	for n in get_parent().get_children():
		if n is CSGBox3D and _is_facade(n.name):
			out.append(n)
	return out


## Alleen de gebouwen, niet de vloer, de kades, de muren of de losse props.
func _is_facade(node_name: String) -> bool:
	var n := node_name.to_lower()
	if n.begins_with("rowplain") or n.begins_with("shed") or n.begins_with("church"):
		return true
	return n.begins_with("gable") and n.length() <= 10


## Een vlak als [normaal, langsrichting, halve diepte, breedte, hoogte].
func _faces(box: CSGBox3D) -> Array:
	var sz := box.size
	if sz.y < 4.0:
		return []
	var half := sz * 0.5
	var out: Array = []
	out.append([Vector3.RIGHT, Vector3.BACK, half.x, sz.z, sz.y])
	out.append([Vector3.LEFT, Vector3.BACK, half.x, sz.z, sz.y])
	out.append([Vector3.BACK, Vector3.RIGHT, half.z, sz.x, sz.y])
	out.append([Vector3.FORWARD, Vector3.RIGHT, half.z, sz.x, sz.y])
	return out


## Kijkt of er ruimte voor het vlak is, zonder physics (CSG levert één samengestelde collider, dus een
## ray vanaf een gevel raakt de hal zelf). In plaats daarvan: bemonster het vlak en kijk of er binnen
## 0,8 m voor het vlak nog een ander massief blok zit. Zo niet, dan kijkt het vlak vrij uit.
func _exposed(solids: Array, box: CSGBox3D, face: Array) -> bool:
	var normal: Vector3 = face[0]
	var along: Vector3 = face[1]
	var depth: float = face[2]
	var width: float = face[3]
	var height: float = face[4]
	var right := Vector3.UP.cross(normal).normalized()
	var centre := box.global_position + normal * (depth + 0.8)
	var samples := [
		centre + Vector3.UP * (height * 0.5 - 1.4),
		centre + Vector3.UP * (height * 0.5 - 1.4) + right * (width * 0.4),
		centre + Vector3.UP * (height * 0.5 - 1.4) - right * (width * 0.4),
		centre + Vector3.UP * 0.0,
	]
	for p in samples:
		if _blocked(solids, box, p):
			return false
	return true


func _blocked(solids: Array, self_box: CSGBox3D, p: Vector3) -> bool:
	var eps := 0.05
	for o in solids:
		if o == self_box:
			continue
		var c: Vector3 = o.global_position
		var h: Vector3 = (o as CSGBox3D).size * 0.5
		if absf(p.x - c.x) <= h.x - eps and absf(p.y - c.y) <= h.y - eps and absf(p.z - c.z) <= h.z - eps:
			return true
	return false


## Alles wat massief is: alle CSG-boxen van de map, zodat muren, kades en vloer ook als "bezet" tellen.
func _solid_boxes() -> Array:
	var out: Array = []
	for n in get_parent().get_children():
		if n is CSGBox3D and (n as CSGBox3D).size.length() > 1.0:
			out.append(n)
	return out


func _windows_on(box: CSGBox3D, face: Array) -> void:
	var normal: Vector3 = face[0]
	var along: Vector3 = face[1]
	var depth: float = face[2]
	var width: float = face[3]
	var height: float = face[4]
	var cols := int(floor(width / WIN_GAP_X))
	if cols < 1:
		return
	var rows := int(floor((height - WIN_FIRST_Y - 0.6) / WIN_GAP_Y)) + 1
	var right := normal.cross(Vector3.UP).normalized()
	for row in rows:
		var y := -height * 0.5 + WIN_FIRST_Y + row * WIN_GAP_Y
		if y > height * 0.5 - WIN.y:
			continue
		for c in cols:
			var off := -(cols - 1) * WIN_GAP_X * 0.5 + c * WIN_GAP_X
			var base := box.global_position + normal * (depth + 0.03) + along * off + Vector3.UP * y
			_frames.append(Transform3D(Basis(right * WIN.x * FRAME_SCALE.x, Vector3.UP * WIN.y * FRAME_SCALE.y, normal), base))
			# Een deel van de ramen is verlicht: deterministisch per positie, zodat een replay gelijk blijft.
			var lit := (int(absf(base.x) * 71.0) + int(absf(base.z) * 37.0) + row * 13) % 10 < 4
			_glass.append(Transform3D(Basis(right * WIN.x, Vector3.UP * WIN.y, normal), base + normal * 0.012))
			_tones.append(Color(1.0, 0.86, 0.6) if lit else Color(0.13, 0.17, 0.24))


func _trim_on(box: CSGBox3D, face: Array) -> void:
	var normal: Vector3 = face[0]
	var along: Vector3 = face[1]
	var depth: float = face[2]
	var width: float = face[3]
	var height: float = face[4]
	var right := normal.cross(Vector3.UP).normalized()
	var basis := Basis(right * width, Vector3.UP * TRIM_H, normal * TRIM_D)
	var at := box.global_position + normal * (depth + TRIM_D * 0.5) + Vector3.UP * (height * 0.5 - TRIM_H * 0.5)
	_trim.append(Transform3D(basis, at))


func _build() -> void:
	_add_quads(_frames, [Color(0.2, 0.17, 0.15)], false, "Frames")
	_add_quads(_glass, _tones, true, "Glass")
	if not _trim.is_empty():
		var mmi := _multimesh(_trim, "Trim")
		var m := _solid(Color(0.2, 0.21, 0.23), 0.55, 0.0)
		mmi.material_override = m
		add_child(mmi)
	_lamp_poles.clear()
	_lamp_heads.clear()
	var z := LAMP_Z_FROM
	while z <= LAMP_Z_TO:
		for side in [-1.0, 1.0]:
			var at := Vector3(side * LAMP_X, LAMP_H * 0.5, z)
			_lamp_poles.append(Transform3D(Basis(Vector3.ONE * 0.1, Vector3.UP * LAMP_H, Vector3.ONE * 0.1), at))
			_lamp_heads.append(Transform3D(Basis(Vector3.ONE * 0.34, Vector3.ONE * 0.34, Vector3.ONE * 0.34), Vector3(side * LAMP_X, LAMP_H + 0.1, z)))
		z += LAMP_Z
	_add_boxes(_lamp_poles, _solid(Color(0.16, 0.17, 0.19), 0.5, 0.4), "LampPosts")
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1.0, 0.86, 0.6)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.8, 0.45)
	head.emission_energy_multiplier = 1.6
	_add_boxes(_lamp_heads, head, "LampHeads")


func _add_quads(xforms: Array[Transform3D], colors: Array[Color], unshaded: bool, node_name: String) -> void:
	if xforms.is_empty():
		return
	var with_colors := colors.size() == xforms.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	# use_colors moet aan staan vóór instance_count: daarna mag het niet meer (Godot-weigert anders).
	mm.use_colors = with_colors
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	if with_colors:
		for i in xforms.size():
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if mm.use_colors:
		m.vertex_color_use_as_albedo = true
	else:
		m.albedo_color = colors[0]
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if unshaded:
		# De kozijnen zijn donker en vangen geen licht; anders vallen ze weg in de schaduw.
		m.albedo_color = Color(0.2, 0.17, 0.15)
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _add_boxes(xforms: Array[Transform3D], mat: Material, node_name: String) -> void:
	if xforms.is_empty():
		return
	var mmi := _multimesh(xforms, node_name)
	mmi.multimesh.mesh = BoxMesh.new()
	mmi.material_override = mat
	add_child(mmi)


func _multimesh(xforms: Array[Transform3D], node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	return mmi


func _solid(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
