class_name Trials
extends RefCounted
## Trials (#325): oefenbanen per map. Solo en lokaal - dezelfde physics en regels als een match, geen
## bots, geen netwerk, geen `NET_VERSION`.
##
## De data staat in `data/trials/<map>.json`: per lijn een naam en een rij checkpoints als [x, y, z].
## De y is een hint: bij het laden zoekt de runner de vloer onder dat punt op, zodat een lijn niet
## stukgaat als de geometrie een centimeter verschuift.
const DIR := "res://data/trials"
const SAVE_PATH := "user://trials.cfg"
const GHOST_DIR := "user://trials_ghost"
const LINE_MAX := 3

## Een checkpoint telt als je er binnen deze straal langskomt.
const PICK_M := 2.4
## Vertrek uit de start (hier voorbij) start de klok.
const START_M := 1.6


static func path_for(map_id: StringName) -> String:
	return "%s/%s.json" % [DIR, map_id]


static func has_map(map_id: StringName) -> bool:
	return FileAccess.file_exists(path_for(map_id))


## Alle lijnen van een map. Leeg als er geen bestand is of het niet leest.
static func load_lines(map_id: StringName) -> Array:
	if not has_map(map_id):
		return []
	var text := FileAccess.get_file_as_string(path_for(map_id))
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	for raw in (data as Dictionary).get("lines", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cps: Array = []
		for p in (raw as Dictionary).get("checkpoints", []):
			if p is Array and (p as Array).size() >= 3:
				cps.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			elif p is Array and (p as Array).size() == 2:
				cps.append(Vector3(float(p[0]), 0.0, float(p[1])))
		if cps.size() < 2:
			continue # een lijn zonder twee punten is geen run
		out.append({
			"id": String((raw as Dictionary).get("id", "line")),
			"name": String((raw as Dictionary).get("name", "Line")),
			"hint": String((raw as Dictionary).get("hint", "")),
			"checkpoints": cps,
		})
	return out


## "0:12.34"; minuten alleen als de run zo lang duurt.
static func format_ms(ms: int) -> String:
	if ms < 0:
		return "--:--"
	var total := float(ms) / 1000.0
	var minutes := int(total / 60.0)
	var seconds := total - float(minutes * 60)
	if minutes > 0:
		return "%d:%05.2f" % [minutes, seconds]
	return "%.2fs" % seconds


## Beste tijd in ms, of 0 als er nog geen is.
static func best_ms(map_id: StringName, line: int) -> int:
	var cfg := _open()
	return int(cfg.get_value(section(map_id), "best_%d" % line, 0))


static func best_ghost_path(map_id: StringName, line: int) -> String:
	return "%s/%s_%d.bin" % [GHOST_DIR, map_id, line]


## Slaat een tijd op als hij sneller is dan de beste. Geeft terug of dat zo was.
static func save_best(map_id: StringName, line: int, ms: int, ghost: PackedFloat32Array = PackedFloat32Array()) -> bool:
	if ms <= 0:
		return false
	var prev := best_ms(map_id, line)
	if prev > 0 and ms >= prev:
		return false
	var cfg := _open()
	cfg.set_value(section(map_id), "best_%d" % line, ms)
	cfg.save(SAVE_PATH)
	if not ghost.is_empty():
		save_ghost(map_id, line, ghost)
	return true


static func save_ghost(map_id: StringName, line: int, ghost: PackedFloat32Array) -> void:
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	var f := FileAccess.open(best_ghost_path(map_id, line), FileAccess.WRITE)
	if f == null:
		push_warning("Trials: kan de ghost niet schrijven voor %s lijn %d" % [map_id, line])
		return
	f.store_32(1) # versie
	f.store_32(ghost.size())
	f.store_buffer(ghost.to_byte_array())
	f.close()


## De ghost als platte reeks [x, y, z, yaw] per sample. Leeg als er geen is.
static func load_ghost(map_id: StringName, line: int) -> PackedFloat32Array:
	var path := best_ghost_path(map_id, line)
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	var version := f.get_32()
	var count := f.get_32()
	if version != 1 or count <= 0:
		f.close()
		return PackedFloat32Array()
	# count is het aantal floats, niet het aantal samples: elk sample is vier floats, dus count * 4 bytes.
	var bytes := f.get_buffer(count * 4)
	f.close()
	return bytes.to_float32_array()


static func section(map_id: StringName) -> String:
	return "trials_%s" % map_id


## Voor de checks en het menu: alles wissen (alleen de trials-opslag).
static func clear_all() -> void:
	var cfg := ConfigFile.new()
	cfg.save(SAVE_PATH)
	for map_id in [&"townhouses", &"foundry", &"rooftops", &"quay", &"skyline"]:
		for line in LINE_MAX:
			var p := best_ghost_path(map_id, line)
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


static func _open() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH) # ontbrekend bestand is geen fout: dan begin je met lege tijden
	return cfg
