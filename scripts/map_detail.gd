extends Node3D
## Detail op de Townhouses-gevels (#322, stijl A: warme gracht, gouden uur).
##
## Alles wat hier gebouwd wordt is **visueel**: MultiMeshes en losse meshes zonder collider, dus de
## navigatie, de bot-routes, de spawns en NET_VERSION merken er niets van. Wat er bij komt:
##
## - ramen met kozijn, alleen op gevelvlakken die vrij naar buiten kijken;
## - deuren op de begane grond van diezelfde vlakken;
## - dakranden, met de teamkleur van de kant waar het gebouw staat (_B blauw, _O oranje), zodat je in
##   één blik ziet welke kant je op kijkt;
## - trapgevels en halsgevels bovenop de gebouwen;
## - lantaarnpalen, meerpalen, bootjes en fietsen langs de kade.
##
## De tinten zijn die van palet A uit `tools/shot_style.gd`.
const WIN := Vector2(0.85, 1.15)
const FRAME_SCALE := Vector2(1.16, 1.12)
const WIN_GAP_X := 2.8
const WIN_GAP_Y := 3.2
const WIN_FIRST_Y := 3.2
const DOOR := Vector2(1.2, 2.3)
const TRIM_H := 0.35
const TRIM_D := 0.5
const GABLE_STEPS := 5
const GABLE_STEP_H := 0.46
const GABLE_DEPTH := 0.4
const GABLE_MAX_W := 7.0
const GABLE_MIN_H := 5.0
const LAMP_X := 5.6
const LAMP_Z := 12.0
const LAMP_Z_FROM := -36.0
const LAMP_Z_TO := 37.0
const LAMP_H := 3.6
const POST_Z := 6.0
const BIKE_Z := 18.0
const BIKE_X := 10.4

## Palet A
const BRICK := Color(0.62, 0.4, 0.24)
const TRIM := Color(0.24, 0.2, 0.17)
const DOOR_WOOD := Color(0.24, 0.15, 0.1)
const GLASS_LIT := Color(1.0, 0.86, 0.6)
const GLASS_DARK := Color(0.12, 0.16, 0.22)
const TEAM_BLUE := Color(0.27, 0.46, 0.62)
const TEAM_ORANGE := Color(0.7, 0.44, 0.18)
const HULL := Color(0.2, 0.16, 0.13)
const STEEL := Color(0.2, 0.21, 0.23)

var _frames: Array[Transform3D] = []
var _glass: Array[Transform3D] = []
var _tones: Array[Color] = []
var _doors: Array[Transform3D] = []
var _door_frames: Array[Transform3D] = []
var _bricks: Array[Transform3D] = []
var _trim_neutral: Array[Transform3D] = []
var _trim_blue: Array[Transform3D] = []
var _trim_orange: Array[Transform3D] = []
var _lamp_poles: Array[Transform3D] = []
var _lamp_heads: Array[Transform3D] = []
var _posts: Array[Transform3D] = []
var _hulls: Array[Transform3D] = []
var _cabins: Array[Transform3D] = []
var _bike_rows: Array[Transform3D] = []


func _ready() -> void:
	var solids := _solid_boxes()
	var boxes := _faced_boxes()
	for box in boxes:
		var building := _is_building(box.name)
		for face in _faces(box):
			if not _exposed(solids, box, face):
				continue
			_windows_on(box, face)
			_trim_on(box, face)
			if building:
				_door_on(box, face)
		if building:
			_gable_on(solids, box)
	_build()
	print("MapDetail: %d ramen, %d deuren, %d dakranden, %d gevelstappen, %d lantaarns, %d boten" % [
		_glass.size(), _doors.size(), _trim_neutral.size() + _trim_blue.size() + _trim_orange.size(),
		_bricks.size(), _lamp_heads.size(), _hulls.size()])


# --- indeling ---------------------------------------------------------------


func _faced_boxes() -> Array[CSGBox3D]:
	var out: Array[CSGBox3D] = []
	for n in get_parent().get_children():
		if n is CSGBox3D and _is_facade(n.name):
			out.append(n)
	return out


## Gevels: de gebouwen, niet de vloer, de kades, de muren of de losse props.
func _is_facade(node_name: String) -> bool:
	var n := node_name.to_lower()
	if n.begins_with("rowplain") or n.begins_with("shed") or n.begins_with("church"):
		return true
	return n.begins_with("gable") and n.length() <= 10


## Een gebouw krijgt ook een deur en een geveltop; een los blok niet.
func _is_building(node_name: String) -> bool:
	var n := node_name.to_lower()
	return n.begins_with("rowplain") or n.begins_with("shed")


## _B hoort bij de blauwe kant, _O bij de oranje; de rest is neutraal.
func _team_of(node_name: String) -> Color:
	var n := String(node_name).to_lower()
	if n.ends_with("_b"):
		return TEAM_BLUE
	if n.ends_with("_o"):
		return TEAM_ORANGE
	return TRIM


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
	var depth: float = face[2]
	var width: float = face[3]
	var height: float = face[4]
	var right := Vector3.UP.cross(normal).normalized()
	var centre := box.global_position + normal * (depth + 0.8)
	var samples := [
		centre + Vector3.UP * (height * 0.5 - 1.4),
		centre + Vector3.UP * (height * 0.5 - 1.4) + right * (width * 0.4),
		centre + Vector3.UP * (height * 0.5 - 1.4) - right * (width * 0.4),
		centre,
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


# --- gevelstukken -----------------------------------------------------------


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
			_tones.append(GLASS_LIT if lit else GLASS_DARK)


## Eén deur per vrij vlak, in het midden, met de onderkant op de vloer van het gebouw.
func _door_on(box: CSGBox3D, face: Array) -> void:
	var normal: Vector3 = face[0]
	var depth: float = face[2]
	var width: float = face[3]
	var height: float = face[4]
	if width < 3.0:
		return
	var right := normal.cross(Vector3.UP).normalized()
	var base := box.global_position + normal * (depth + 0.03) + Vector3.UP * (-height * 0.5 + DOOR.y * 0.5 + 0.05)
	_door_frames.append(Transform3D(Basis(right * DOOR.x * 1.2, Vector3.UP * DOOR.y * 1.06, normal), base))
	_doors.append(Transform3D(Basis(right * DOOR.x, Vector3.UP * DOOR.y, normal), base + normal * 0.012))


func _trim_on(box: CSGBox3D, face: Array) -> void:
	var normal: Vector3 = face[0]
	var along: Vector3 = face[1]
	var depth: float = face[2]
	var width: float = face[3]
	var height: float = face[4]
	var right := normal.cross(Vector3.UP).normalized()
	var basis := Basis(right * width, Vector3.UP * TRIM_H, normal * TRIM_D)
	var at := box.global_position + normal * (depth + TRIM_D * 0.5) + Vector3.UP * (height * 0.5 - TRIM_H * 0.5)
	var xf := Transform3D(basis, at)
	match _team_of(box.name):
		TEAM_BLUE:
			_trim_blue.append(xf)
		TEAM_ORANGE:
			_trim_orange.append(xf)
		_:
			_trim_neutral.append(xf)


## Geveltop: trapgevel (stapel die smaller wordt) of halsgevel (smalle hals met een blok erop), bovenop
## het gebouw, aan de kant die vrij uitkijkt. Puur decor: het staat boven de bestaande doos.
func _gable_on(solids: Array, box: CSGBox3D) -> void:
	if box.size.y < GABLE_MIN_H:
		return
	var best_face: Array = []
	var best_width := 0.0
	for face in _faces(box):
		if not _exposed(solids, box, face):
			continue
		var w: float = face[3]
		if w > best_width:
			best_width = w
			best_face = face
	if best_face.is_empty():
		return
	var normal: Vector3 = best_face[0]
	var depth: float = best_face[2]
	var width: float = best_face[3]
	var height: float = best_face[4]
	var right := normal.cross(Vector3.UP).normalized()
	var top := box.global_position + Vector3.UP * (height * 0.5)
	var neck := (int(absf(box.global_position.x) + absf(box.global_position.z)) % 2) == 1
	var base_w := minf(width, GABLE_MAX_W)
	for i in GABLE_STEPS:
		var frac := 1.0 - float(i) / float(GABLE_STEPS)
		var step_w := base_w * frac
		if neck:
			# Halsgevel: een smalle hals, met bovenin een breder blok.
			step_w = base_w * (0.4 if i < GABLE_STEPS - 1 else 0.6)
		var y := top + Vector3.UP * (GABLE_STEP_H * (float(i) + 0.5))
		var basis := Basis(right * maxf(0.6, step_w), Vector3.UP * GABLE_STEP_H, normal * (GABLE_DEPTH + 0.02))
		_bricks.append(Transform3D(basis, y + normal * depth * 0.5))


# --- props ------------------------------------------------------------------


func _build() -> void:
	_add_quads(_frames, [TRIM], false, "Frames")
	_add_quads(_glass, _tones, true, "Glass")
	_add_quads(_door_frames, [TRIM], false, "DoorFrames")
	_add_quads(_doors, [DOOR_WOOD], true, "Doors")
	if not _bricks.is_empty():
		var gables := _multimesh(_bricks, "Gables")
		gables.multimesh.mesh = BoxMesh.new()
		gables.material_override = _solid(BRICK, 0.92, 0.0)
		add_child(gables)
	for pair in [[_trim_neutral, TRIM, "Trim"], [_trim_blue, TEAM_BLUE, "TrimBlue"], [_trim_orange, TEAM_ORANGE, "TrimOrange"]]:
		var xforms: Array = pair[0]
		if xforms.is_empty():
			continue
		var mmi := _multimesh(xforms, String(pair[2]))
		mmi.material_override = _solid(pair[1], 0.6, 0.0)
		add_child(mmi)
	_lamps()
	_mooring()
	_boats()
	_bikes()


func _lamps() -> void:
	_lamp_poles.clear()
	_lamp_heads.clear()
	var z := LAMP_Z_FROM
	while z <= LAMP_Z_TO:
		for side in [-1.0, 1.0]:
			_lamp_poles.append(Transform3D(Basis(Vector3.ONE * 0.1, Vector3.UP * LAMP_H, Vector3.ONE * 0.1), Vector3(side * LAMP_X, LAMP_H * 0.5, z)))
			_lamp_heads.append(Transform3D(Basis(Vector3.ONE * 0.34, Vector3.ONE * 0.34, Vector3.ONE * 0.34), Vector3(side * LAMP_X, LAMP_H + 0.1, z)))
		z += LAMP_Z
	_add_boxes(_lamp_poles, _solid(STEEL, 0.5, 0.4), "LampPosts")
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1.0, 0.86, 0.6)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.8, 0.45)
	head.emission_energy_multiplier = 1.6
	_add_boxes(_lamp_heads, head, "LampHeads")


## Meerpalen langs de kade, om de 6 m, net buiten de waterlijn.
func _mooring() -> void:
	_posts.clear()
	var z := -34.0
	while z <= 34.0:
		if absf(z) > 2.5: # niet in de doorvaart van de brug
			for side in [-1.0, 1.0]:
				_posts.append(Transform3D(Basis(Vector3.ONE * 0.16, Vector3.UP * 0.9, Vector3.ONE * 0.16), Vector3(side * 5.3, 0.35, z)))
		z += POST_Z
	_add_boxes(_posts, _solid(Color(0.16, 0.13, 0.11), 0.85, 0.0), "MooringPosts")


## Drie extra bootjes in de gracht, naast de boten die de map al heeft (BoatA/B).
func _boats() -> void:
	_hulls.clear()
	_cabins.clear()
	for at in [Vector3(2.4, -2.85, -30.0), Vector3(-2.4, -2.85, 31.0), Vector3(2.2, -2.85, 44.0)]:
		_hulls.append(Transform3D(Basis(Vector3(2.4, 0.9, 5.4), Vector3.UP, Vector3(2.4, 0.9, 5.4)), at))
		_cabins.append(Transform3D(Basis(Vector3(1.4, 0.7, 2.2), Vector3.UP, Vector3(1.4, 0.7, 2.2)), at + Vector3(0, 0.75, -0.6)))
	if not _hulls.is_empty():
		_add_boxes(_hulls, _solid(HULL, 0.7, 0.1), "BoatHulls")
		_add_boxes(_cabins, _solid(Color(0.4, 0.32, 0.24), 0.8, 0.0), "BoatCabins")


## Fietsen tegen de kademuur: één dunne vorm per fiets.
func _bikes() -> void:
	_bike_rows.clear()
	var z := -30.0
	while z <= 30.0:
		for side in [-1.0, 1.0]:
			_bike_rows.append(Transform3D(Basis(Vector3(0.12, 1.0, 1.7), Vector3.UP, Vector3(0.12, 1.0, 1.7)), Vector3(side * BIKE_X, 0.5, z)))
		z += BIKE_Z
	_add_boxes(_bike_rows, _solid(Color(0.18, 0.18, 0.2), 0.6, 0.3), "Bikes")


# --- helpers ----------------------------------------------------------------


func _add_quads(xforms: Array[Transform3D], colors: Array[Color], unshaded: bool, node_name: String) -> void:
	if xforms.is_empty():
		return
	var with_colors := colors.size() == xforms.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	# use_colors moet aan staan vóór instance_count: daarna mag het niet meer.
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
	if with_colors:
		m.vertex_color_use_as_albedo = true
	else:
		m.albedo_color = colors[0]
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
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
