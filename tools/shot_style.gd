extends Node
## Stijlvarianten voor Townhouses renderen zonder de map aan te passen (#322, stijlvoorstel).
##
## Laadt de map, zet per node-soort een materiaal uit het gekozen palet, en schiet de drie views van het
## kade/ophaalbrug-stuk. De map op schijf blijft ongemoeid: dit is een voorstel, geen wijziging.
##
##   xvfb-run -a godot --path . res://tools/shot_style.tscn -- --out DIR
var out := "/tmp"
var map: Node3D
var env: Environment

const VIEWS := {
	"quay": [Vector3(0, 11, 32), Vector3(0, 3, 2)],
	"drawbridge": [Vector3(14, 6, 10), Vector3(0, 6, 0)],
	"canal": [Vector3(0, 2.0, 34), Vector3(0, -1.0, 0)],
}

## Twee richtingen. Alle kleuren zijn tinten: de gegenereerde steen-/pantexturen blijven eronder zitten.
const PALETTES := {
	"a": {
		"brick": Color(0.62, 0.4, 0.24),
		"roof": Color(0.26, 0.44, 0.4),
		"stone": Color(0.5, 0.44, 0.4),
		"pave": Color(0.46, 0.42, 0.36),
		"wood": Color(0.3, 0.22, 0.15),
		"steel": Color(0.2, 0.22, 0.24),
		"sun": Color(1.0, 0.84, 0.62),
		"sky_top": Color(0.22, 0.32, 0.5),
		"sky_hor": Color(0.86, 0.72, 0.55),
		"fog": Color(0.82, 0.72, 0.6),
		"sun_energy": 1.35,
		"fog_density": 0.0014,
	},
	"b": {
		"brick": Color(0.44, 0.42, 0.42),
		"roof": Color(0.24, 0.27, 0.34),
		"stone": Color(0.4, 0.42, 0.46),
		"pave": Color(0.4, 0.42, 0.45),
		"wood": Color(0.26, 0.24, 0.24),
		"steel": Color(0.22, 0.25, 0.29),
		"sun": Color(0.86, 0.92, 1.0),
		"sky_top": Color(0.2, 0.3, 0.44),
		"sky_hor": Color(0.66, 0.74, 0.8),
		"fog": Color(0.68, 0.76, 0.84),
		"sun_energy": 1.1,
		"fog_density": 0.002,
	},
}

var _tex := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	_tex = {
		"brick": load("res://assets/maps/townhouses/brick.png"),
		"roof": load("res://assets/maps/townhouses/rooftile.png"),
		"cobble": load("res://assets/maps/townhouses/cobble.png"),
		"quay": load("res://assets/maps/townhouses/quay.png"),
	}
	for key in PALETTES:
		await _render(key, PALETTES[key])
	print("SHOT STYLE: done")
	get_tree().quit()


func _render(key: String, p: Dictionary) -> void:
	_teardown()
	map = (load("res://scenes/maps/townhouses.tscn") as PackedScene).instantiate() as Node3D
	add_child(map)
	env = (map.get_node("WorldEnvironment") as WorldEnvironment).environment.duplicate() as Environment
	(map.get_node("WorldEnvironment") as WorldEnvironment).environment = env
	_style_sky(p)
	for n in _csg_nodes(map):
		# Teamkleuren blijven staan. In een teamshooter moet je aan de wand zien welke kant je op kijkt,
		# dus het palet raakt alleen de neutrale materialen (review Chief of staff op #405).
		if n is CSGPrimitive3D and _is_team(n):
			continue
		var mat := _material_for(n.name, p)
		# Een CSGCombiner3D heeft geen eigen materiaal (alleen de primitives); die slaan we over.
		if n is CSGPrimitive3D or n is MeshInstance3D:
			n.set("material", mat)
	_add_windows()
	_add_lights()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for view in VIEWS:
		var at: Array = VIEWS[view]
		cam.global_position = at[0]
		cam.look_at(at[1], Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/style_%s_%s.png" % [out, key, view]
		img.save_png(path)
		print("saved ", path)
	cam.queue_free()


## Ramen op de gevelblokken. Alleen de huis-knopen (Gable/House/Row), niet de buitenmuren: daar zitten ze
## op vlakken die je nooit ziet, en dat maakte de eerste poging onbruikbaar.
func _add_windows() -> void:
	var quads: Array[Transform3D] = []
	var tones: Array[Color] = []
	var win := Vector2(0.95, 1.35)
	for n in map.find_children("*", "CSGBox3D", true, false):
		var nm := String(n.name).to_lower()
		if not (nm.begins_with("gable") or nm.begins_with("house") or nm.begins_with("row")):
			continue
		var box := n as CSGBox3D
		var sz := box.size
		if sz.x < 4.0 or sz.z < 4.0 or sz.y < 4.0:
			continue
		var half := sz * 0.5
		var faces := [
			[Vector3.RIGHT, Vector3.BACK, half.x, sz.z],
			[Vector3.LEFT, Vector3.BACK, half.x, sz.z],
			[Vector3.BACK, Vector3.RIGHT, half.z, sz.x],
			[Vector3.FORWARD, Vector3.RIGHT, half.z, sz.x],
		]
		for f in faces:
			var normal: Vector3 = f[0]
			var along: Vector3 = f[1]
			var depth: float = f[2]
			var width: float = f[3]
			var cols := int(floor(width / 2.8))
			if cols < 1:
				continue
			for row in 2:
				var y := -half.y + 3.2 + row * 3.2
				if y > half.y - win.y:
					continue
				for c in cols:
					var off := -(cols - 1) * 1.4 + c * 2.8
					var base := box.global_position + normal * (depth + 0.04) + along * off + Vector3.UP * y
					var right := normal.cross(Vector3.UP).normalized()
					# Kozijn: een iets groter donker vlak, dan het glas er een paar mm voor.
					quads.append(Transform3D(Basis(right * win.x * 1.16, Vector3.UP * win.y * 1.12, normal), base))
					tones.append(Color(0.2, 0.17, 0.15))
					var lit := (int(absf(base.x) * 71.0) + int(absf(base.z) * 37.0) + row * 13) % 10 < 4
					var glass := base + normal * 0.012
					quads.append(Transform3D(Basis(right * win.x, Vector3.UP * win.y, normal), glass))
					tones.append(Color(1.0, 0.86, 0.6) if lit else Color(0.13, 0.17, 0.24))
	if quads.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = quads.size()
	for i in quads.size():
		mm.set_instance_transform(i, quads[i])
		mm.set_instance_color(i, tones[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map.add_child(mmi)
	print("  windows: ", quads.size())


## Twee warme lampen bij de ophaalbrug, zodat dat stuk een eigen licht heeft.
func _add_lights() -> void:
	for at in [Vector3(9.0, 4.2, 4.0), Vector3(-9.0, 4.2, 4.0)]:
		var l := OmniLight3D.new()
		l.position = at
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 2.2
		l.omni_range = 14.0
		map.add_child(l)


func _teardown() -> void:
	if map != null and is_instance_valid(map):
		map.queue_free()
	map = null


func _csg_nodes(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "CSGShape3D", true, false):
		out.append(n)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n)
	return out


## Welk materiaal bij welke node hoort, op de naam. De map is met de hand opgebouwd en de namen zeggen
## wat het is (Gable, RoofSurf, QuayPave, Bridge, Portal, Wall), dus dat is betrouwbaarder dan de kleur
## van het huidige materiaal raden.
func _material_for(node_name: String, p: Dictionary) -> StandardMaterial3D:
	var n := node_name.to_lower()
	if n.begins_with("roof") or n.begins_with("rowfall"):
		return _mat(p["roof"], "roof", 1.0)
	if n.begins_with("gable") or n.begins_with("house") or n.begins_with("row"):
		return _mat(p["brick"], "brick", 1.4)
	if n.begins_with("quaypave") or n.begins_with("canalpave"):
		return _mat(p["pave"], "quay", 0.5)
	if n.begins_with("canalstep") or n.begins_with("ground") or n.begins_with("pave"):
		return _mat(p["pave"], "cobble", 0.7)
	if n.begins_with("bridge") or n.begins_with("drawdeck"):
		return _mat(p["wood"], "cobble", 0.8)
	if n.begins_with("portal"):
		return _mat(p["steel"], "", 0.0, true)
	if n.begins_with("wall"):
		return _mat(p["stone"], "cobble", 0.6)
	return _mat(p["stone"], "cobble", 0.6)


## Team-materiaal herkennen aan de kleur: Mat_team_blue (0.27, 0.46, 0.62) en Mat_team_orange
## (0.7, 0.44, 0.18). Een palet mag die niet overschrijven.
const TEAM_COLORS := [Color(0.27, 0.46, 0.62), Color(0.7, 0.44, 0.18)]


func _is_team(n: Node) -> bool:
	var m := (n as CSGPrimitive3D).material
	if m is StandardMaterial3D:
		var c := (m as StandardMaterial3D).albedo_color
		for t in TEAM_COLORS:
			if absf(c.r - t.r) < 0.06 and absf(c.g - t.g) < 0.06 and absf(c.b - t.b) < 0.06:
				return true
	# De spawnwanden heten zo; die houden hun teamkleur ook als het materiaal ooit verschuift.
	var nm := String(n.name).to_lower()
	return nm.begins_with("wallnorth") or nm.begins_with("wallsouth") or nm.begins_with("spawnwall")


func _mat(col: Color, tex_key: String, scale: float, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5 if metal else 0.9
	m.metallic = 0.6 if metal else 0.0
	if tex_key != "" and _tex.has(tex_key):
		m.albedo_texture = _tex[tex_key]
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _style_sky(p: Dictionary) -> void:
	var sky := env.sky
	if sky == null:
		sky = Sky.new()
	var mat := (sky.sky_material as ProceduralSkyMaterial)
	if mat == null:
		mat = ProceduralSkyMaterial.new()
		sky.sky_material = mat
	mat = mat.duplicate() as ProceduralSkyMaterial
	mat.sky_top_color = p["sky_top"]
	mat.sky_horizon_color = p["sky_hor"]
	sky.sky_material = mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_light_color = p["fog"]
	env.fog_density = p["fog_density"]
	env.ambient_light_energy = 0.45
	var sun := map.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_color = p["sun"]
		sun.light_energy = p["sun_energy"]
