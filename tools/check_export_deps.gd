extends Node
## Nothing the game exports may depend on a folder the export leaves out. export_presets.cfg drops
## tools/, docs/ and testmodels/ (exclude_filter), so a scene that points into one of them loads in the
## editor and in every other check but fails in a release build: v0.5.21's first export lost all eight
## muzzle flashes (and the gun scenes holding them) to a @tool helper script in tools/.
## Reads every .tscn/.tres outside the excluded folders for an ext_resource into one, and every .gd for
## a preload() into one (a load() is a runtime choice, e.g. a dev tool, and is not counted).
##   godot --headless res://tools/check_export_deps.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var excluded := _excluded_dirs()
	_ok(excluded.has("tools/"), "export_presets.cfg leaves tools/ out (%s)" % ", ".join(excluded))
	var files: Array[String] = []
	_walk("res://", excluded, files)
	_ok(files.size() > 100, "%d exported text resources and scripts read" % files.size())
	var ext_re := RegEx.create_from_string("path=\"res://([^\"]+)\"")
	var pre_re := RegEx.create_from_string("preload\\(\\s*\"res://([^\"]+)\"")
	var bad := 0
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		var re := pre_re if f.ends_with(".gd") else ext_re
		for m in re.search_all(text):
			var target := m.get_string(1)
			for ex in excluded:
				if target.begins_with(ex):
					bad += 1
					_ok(false, "%s needs res://%s, which the export leaves out" % [f, target])
	_ok(bad == 0, "no exported file depends on an excluded folder")
	print("EXPORT DEPS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## The folders in every preset's exclude_filter, as "name/" (only "dir/*" patterns).
func _excluded_dirs() -> Array[String]:
	var out: Array[String] = []
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return out
	for section in cfg.get_sections():
		if not cfg.has_section_key(section, "exclude_filter"):
			continue
		for part in String(cfg.get_value(section, "exclude_filter")).split(",", false):
			var p := part.strip_edges()
			if p.ends_with("/*") and not out.has(p.trim_suffix("*")):
				out.append(p.trim_suffix("*"))
	return out


func _walk(dir: String, excluded: Array[String], out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		var rel := (dir + sub).trim_prefix("res://") + "/"
		if excluded.has(rel):
			continue
		_walk(dir + sub + "/", excluded, out)
	for f in d.get_files():
		if f.get_extension() in ["tscn", "tres", "gd"]:
			out.append(dir + f)
