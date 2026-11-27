extends Node3D
## Eén Trials-run (#325): checkpoints, klok, beste tijd en de ghost. Solo, dus geen autoriteit of
## replicatie: de runner hangt aan de map en de lokale pawn.
##
## Regels (zoals een match): dezelfde pawn, dezelfde physics, geen cheats. Vallen in het water zet je
## terug op je laatste checkpoint en de klok loopt door; je kunt een checkpoint niet overslaan, want
## alleen de volgende telt.
signal finished(ms: int, is_best: bool)
signal line_switched(index: int)
signal run_started

const MAP_DETAIL_BEAM := Vector3(0.9, 6.0, 0.9)
const MARK_R := 1.5
const START_Y := 8.0 # waar de vloerprobe begint

var map_id: StringName = &"townhouses"
var line_index := 0
var lines: Array = []
var checkpoints: Array[Vector3] = []
var player: Player
var map_node: Node3D

var running := false # klok loopt
var finished_run := false
var next_cp := 1
var run_ms := 0
var best := 0
var falls := 0

var _start_point := Vector3.ZERO
var _last_safe := Vector3.ZERO
var _recording := PackedFloat32Array()
var _rec_accum := 0.0
var _sample_hz := 30.0 # 30 Hz is genoeg voor een ghost en houdt de opname klein

var _markers: Array[MeshInstance3D] = []
var _ghost: MeshInstance3D
var _ghost_data := PackedFloat32Array()
var _ghost_t := 0.0
var _verbose := true


func setup(node: Node3D, pawn: Player, map: StringName, line := 0) -> bool:
	map_node = node
	player = pawn
	map_id = map
	lines = Trials.load_lines(map_id)
	if lines.is_empty():
		push_warning("Trials: geen lijnen voor %s" % map_id)
		return false
	line_index = clampi(line, 0, lines.size() - 1)
	return _load_line()


func current_line() -> Dictionary:
	if line_index < 0 or line_index >= lines.size():
		return {}
	return lines[line_index]


func _load_line() -> bool:
	if lines.is_empty():
		return false
	var line := current_line()
	var raw: Array = line["checkpoints"]
	checkpoints.clear()
	for p in raw:
		checkpoints.append(_floor_at(p))
	if checkpoints.size() < 2:
		push_warning("Trials: lijn %s heeft te weinig bruikbare checkpoints" % String(line.get("id", "?")))
		return false
	best = Trials.best_ms(map_id, line_index)
	_ghost_data = Trials.load_ghost(map_id, line_index)
	_build_markers()
	_place_player()
	_reset_run()
	if _verbose:
		print("Trials: %s / %s, %d checkpoints, beste %s" % [map_id, line["name"], checkpoints.size(), Trials.format_ms(best)])
	return true


## Zoekt de vloer onder een punt. Zonder vloer blijft de hint-Y staan, zodat de check kan melden dat er
## iets niet klopt in plaats van stil te verdwijnen.
func _floor_at(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := Vector3(p.x, p.y + START_Y, p.z)
	var to := Vector3(p.x, p.y - 4.0, p.z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return p
	return Vector3(p.x, float((hit["position"] as Vector3).y) + 0.05, p.z)


func _place_player() -> void:
	if player == null:
		return
	player.global_position = checkpoints[0]
	player.velocity = Vector3.ZERO
	_start_point = checkpoints[0]
	_last_safe = checkpoints[0]


func _reset_run() -> void:
	running = false
	finished_run = false
	next_cp = 1
	run_ms = 0
	falls = 0
	_recording = PackedFloat32Array()
	_rec_accum = 0.0
	_ghost_t = 0.0
	if _ghost != null:
		_ghost.global_position = checkpoints[0] if not checkpoints.is_empty() else Vector3.ZERO
		_ghost.visible = not _ghost_data.is_empty()
	_update_markers()


func restart() -> void:
	_place_player()
	_reset_run()


func next_line() -> void:
	if lines.is_empty():
		return
	line_index = (line_index + 1) % lines.size()
	_clear_markers()
	_load_line()
	line_switched.emit(line_index)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			restart()
			get_viewport().set_input_as_handled()
		KEY_T:
			next_line()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.is_dead:
		return
	if not finished_run:
		if not running:
			# De klok start pas als je echt van de start wegloopt; anders telt de spawn mee.
			if _flat_distance(player.global_position, checkpoints[0]) > Trials.START_M:
				running = true
				run_started.emit()
		if running:
			run_ms += int(roundi(delta * 1000.0))
			_record(delta)
			_check_fall()
			_check_checkpoints()
	_update_ghost(delta)
	_update_markers()


func _record(delta: float) -> void:
	# 30 Hz: niet elke tick, zodat een lange run geen megabytes wordt.
	_rec_accum += delta
	if _rec_accum < 1.0 / _sample_hz:
		return
	_rec_accum = 0.0
	_recording.append(player.global_position.x)
	_recording.append(player.global_position.y)
	_recording.append(player.global_position.z)
	_recording.append(player.rotation.y)


func _check_fall() -> void:
	if player.global_position.y > -4.0:
		_last_safe = player.global_position
		return
	# In het water: terug naar het laatste checkpoint. De klok loopt door en de run blijft geldig; dit is
	# een oefenbaan, geen straf.
	falls += 1
	var back := checkpoints[maxi(0, next_cp - 1)]
	player.global_position = back + Vector3.UP * 1.2
	player.velocity = Vector3.ZERO
	_last_safe = back


func _check_checkpoints() -> void:
	if next_cp >= checkpoints.size():
		return
	if _flat_distance(player.global_position, checkpoints[next_cp]) > Trials.PICK_M:
		return
	if next_cp == checkpoints.size() - 1:
		_finish()
		return
	next_cp += 1
	_last_safe = checkpoints[next_cp - 1]


func _finish() -> void:
	running = false
	finished_run = true
	next_cp = checkpoints.size()
	var is_best := Trials.save_best(map_id, line_index, run_ms, _recording)
	if is_best:
		best = run_ms
		_ghost_data = _recording.duplicate()
	finished.emit(run_ms, is_best)
	_update_markers()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- markers en ghost -------------------------------------------------------


func _build_markers() -> void:
	_clear_markers()
	for i in checkpoints.size():
		var m := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = MARK_R * 0.72
		mesh.outer_radius = MARK_R
		m.mesh = mesh
		m.position = checkpoints[i] + Vector3.UP * 0.08
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.9, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.8
		m.material_override = mat
		m.set_meta("index", i)
		add_child(m)
		_markers.append(m)
		var beam := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = MAP_DETAIL_BEAM
		beam.mesh = box
		beam.position = checkpoints[i] + Vector3.UP * MAP_DETAIL_BEAM.y * 0.5
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.35, 0.8, 1.0, 0.12)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.emission_enabled = true
		bmat.emission = Color(0.35, 0.8, 1.0)
		bmat.emission_energy_multiplier = 0.35
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam.material_override = bmat
		beam.set_meta("index", i)
		beam.set_meta("beam", true)
		add_child(beam)
		_markers.append(beam)
	_build_ghost()
	_update_markers()


func _build_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	# De ghost is alleen het lichaam: geen wapen, geen animatie (besluit Gianni op #325).
	_ghost = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	_ghost.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost.material_override = mat
	_ghost.visible = not _ghost_data.is_empty()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)


func _update_ghost(delta: float) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	if _ghost_data.size() < 8:
		_ghost.visible = false
		return
	_ghost.visible = true
	var samples := _ghost_data.size() / 4
	var dur := float(samples - 1) / _sample_hz
	if running:
		_ghost_t += delta
	elif finished_run:
		_ghost_t = minf(_ghost_t, dur)
	if dur <= 0.0:
		return
	_ghost_t = fposmod(_ghost_t, dur + 0.75) # korte pauze aan het eind, dan opnieuw
	var t := minf(_ghost_t, dur)
	var f := t * _sample_hz
	var i := clampi(int(floor(f)), 0, samples - 2)
	var frac := clampf(f - float(i), 0.0, 1.0)
	var a := Vector3(_ghost_data[i * 4], _ghost_data[i * 4 + 1], _ghost_data[i * 4 + 2])
	var b := Vector3(_ghost_data[(i + 1) * 4], _ghost_data[(i + 1) * 4 + 1], _ghost_data[(i + 1) * 4 + 2])
	var yaw_a := _ghost_data[i * 4 + 3]
	var yaw_b := _ghost_data[(i + 1) * 4 + 3]
	_ghost.global_position = a.lerp(b, frac)
	_ghost.rotation.y = lerp_angle(yaw_a, yaw_b, frac)


func _update_markers() -> void:
	for m in _markers:
		if not is_instance_valid(m):
			continue
		var i := int(m.get_meta("index", -1))
		var is_beam := bool(m.get_meta("beam", false))
		var mat := m.material_override as StandardMaterial3D
		if mat == null:
			continue
		var col: Color
		if finished_run:
			col = Color(0.4, 1.0, 0.6)
		elif i < next_cp:
			col = Color(0.35, 0.5, 0.55) # gehad: gedempt
		elif i == next_cp:
			col = Color(1.0, 0.86, 0.35) # volgende
		else:
			col = Color(0.4, 0.9, 1.0)
		mat.albedo_color = Color(col.r, col.g, col.b, 0.12 if is_beam else 1.0)
		mat.emission = col
		mat.emission_energy_multiplier = 1.2 if i == next_cp and not is_beam else (0.35 if is_beam else 0.7)


func _clear_markers() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()


func progress_text() -> String:
	if checkpoints.is_empty():
		return "0/0"
	return "%d/%d" % [mini(next_cp, checkpoints.size() - 1), checkpoints.size() - 1]


func delta_vs_best() -> String:
	if best <= 0 or not running:
		return ""
	var d := run_ms - best
	if absf(float(d)) < 5.0:
		return "gelijk"
	return "%s%s" % ["-" if d < 0 else "+", Trials.format_ms(absi(d))]
