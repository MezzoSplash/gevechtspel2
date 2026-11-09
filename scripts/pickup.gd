class_name Pickup
extends Node3D
## One map pickup (#144): a low octagonal plinth, an emissive ring in the type's colour and a crystal
## floating above it. Purely visual - shared/pickups.gd owns the state and the effect. Built from the
## same procedural crystal parts as the character, so it needs no art assets.

const FLOAT_H := 0.55 # crystal centre above the plinth top
const SPIN := 30.0 # deg/s
const BOB := 0.04
const RING_SEGS := 24

var pickup_id := 0
var type_id: StringName = &"heal"
var _crystal: Node3D
var _ring: MeshInstance3D
var _fill: Array[MeshInstance3D] = []
var _t := 0.0
var _taken := false
var _respawn := 0.0
var _timer := 0.0
var _glow: StandardMaterial3D
var _chime: AudioStreamPlayer3D


func setup(t: StringName) -> void:
	type_id = t
	var info := Pickups.type_info(t)
	var col: Color = info["color"]
	_glow = CrystalMesh.glow_material(col)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.13, 0.15)
	dark.roughness = 0.8
	dark.metallic = 0.2

	var base := MeshInstance3D.new()
	base.mesh = CrystalMesh.part(&"pickup_base")
	base.material_override = dark
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)

	_ring = MeshInstance3D.new()
	_ring.mesh = CrystalMesh.ring_mesh(0.20, 0.255, RING_SEGS)
	_ring.material_override = _glow
	_ring.position = Vector3(0, 0.345, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# Respawn fill: one thin arc segment per step around the ring, lit as the timer runs out.
	for i in RING_SEGS:
		var seg := MeshInstance3D.new()
		var a0 := TAU * i / RING_SEGS
		var a1 := TAU * (i + 1) / RING_SEGS
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var p00 := Vector3(cos(a0) * 0.265, 0, sin(a0) * 0.265)
		var p01 := Vector3(cos(a0) * 0.30, 0, sin(a0) * 0.30)
		var p10 := Vector3(cos(a1) * 0.265, 0, sin(a1) * 0.265)
		var p11 := Vector3(cos(a1) * 0.30, 0, sin(a1) * 0.30)
		for v in [p00, p11, p10, p00, p01, p11]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		seg.mesh = st.commit()
		seg.material_override = _glow
		seg.position = Vector3(0, 0.35, 0)
		seg.visible = false
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_fill.append(seg)

	_crystal = Node3D.new()
	_crystal.position = Vector3(0, FLOAT_H, 0)
	add_child(_crystal)
	match t:
		&"knives":
			for s in [-1.0, 1.0]:
				var shard := MeshInstance3D.new()
				shard.mesh = CrystalMesh.part(&"pickup_shard")
				shard.material_override = CrystalMesh.glow_material(col)
				shard.rotation.z = deg_to_rad(38.0 * s)
				shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_crystal.add_child(shard)
		&"shield":
			var rock := MeshInstance3D.new()
			rock.mesh = CrystalMesh.part(&"pickup_shield")
			rock.material_override = CrystalMesh.shell_material()
			rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_crystal.add_child(rock)
			var core := MeshInstance3D.new()
			core.mesh = CrystalMesh.part(&"spark")
			core.scale = Vector3.ONE * 2.2
			core.material_override = _glow
			_crystal.add_child(core)
		_:
			var heart := MeshInstance3D.new()
			heart.mesh = CrystalMesh.part(&"pickup_heart")
			heart.material_override = CrystalMesh.glow_material(col)
			heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_crystal.add_child(heart)

	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.6
	light.omni_range = 3.0
	light.position = Vector3(0, 0.7, 0)
	add_child(light)

	_chime = AudioStreamPlayer3D.new()
	_chime.stream = preload("res://assets/sounds/knife_hit.wav")
	_chime.unit_size = 6.0
	_chime.max_distance = 24.0
	add_child(_chime)


func set_taken(respawn: float) -> void:
	_taken = true
	_respawn = maxf(respawn, 0.01)
	_timer = respawn
	if _crystal:
		_crystal.visible = false
	if _ring:
		_ring.transparency = 0.8 # the ring dims to ~20% while the pad recharges
	_play(float(Pickups.type_info(type_id)["pitch"]))
	for s in _fill:
		s.visible = false


func set_ready() -> void:
	_taken = false
	_timer = 0.0
	if _crystal:
		_crystal.visible = true
	if _ring:
		_ring.transparency = 0.0
	for s in _fill:
		s.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _crystal and _crystal.visible:
		_crystal.rotation.y += deg_to_rad(SPIN) * delta
		_crystal.position.y = FLOAT_H + sin(_t * 1.6) * BOB
	if not _taken:
		return
	_timer = maxf(_timer - delta, 0.0)
	var done := 1.0 - _timer / _respawn
	var lit := int(round(done * _fill.size()))
	for i in _fill.size():
		_fill[i].visible = i < lit


func _play(pitch: float) -> void:
	if _chime == null or _chime.stream == null:
		return
	_chime.pitch_scale = pitch
	_chime.play()
