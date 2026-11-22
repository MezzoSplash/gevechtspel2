extends Node
## #356: one source for the build version, and a protocol/build mismatch a player can read.
##   godot --headless --path . res://tools/check_version_source.tscn   → "VERSION SOURCE CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


## The version the export presets stamp into the binary's file properties.
func _preset_version() -> String:
	var f := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("application/product_version="):
			return line.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""


func _ready() -> void:
	var setting := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	_ok(setting != "", "project.godot has application/config/version (%s)" % setting)
	_ok(Game.build_version() == setting.trim_prefix("v"), "Game.build_version() reads project.godot")
	_ok(Game.build_version().contains("."), "the build looks like a release (%s)" % Game.build_version())
	var preset := _preset_version()
	_ok(preset != "" and preset == Game.build_version(), "export_presets.cfg matches the build (preset %s)" % preset)
	_ok(Game.NET_VERSION != Game.build_version(), "the protocol is its own number (%s vs build %s)" % [Game.NET_VERSION, Game.build_version()])

	var info := ServerQuery.info()
	_ok(str(info.get("v", "")) == Game.NET_VERSION, "info() keeps v as the protocol (%s)" % info.get("v", ""))
	_ok(str(info.get("build", "")) == Game.build_version(), "info() carries the build (%s)" % info.get("build", ""))
	_ok(info.has("map") and info.has("players") and info.has("bots"), "the rest of the info query is unchanged")

	var line := MainMenu.version_line()
	_ok(line.contains("v" + Game.build_version()) and line.contains("protocol " + Game.NET_VERSION),
		"menu shows build and protocol (%s)" % line)

	var older := VersionNotice.message("0.5.20", "0.5.21", "0.6.0", "0.6.1")
	_ok(older.contains("protocol 0.5.20") and older.contains("protocol 0.5.21"), "text names both protocols")
	_ok(older.contains("build 0.6.0") and older.contains("build 0.6.1"), "text names both builds")
	_ok(older.contains("niet meespelen") and older.contains("netwerkberichten"), "text says why the join is refused")
	_ok(older.contains("Download de nieuwste versie"), "older client gets the download hint")
	_ok(not VersionNotice.message("0.5.21", "0.5.20", "0.6.1", "0.6.0").contains("Download"),
		"newer client gets the host hint instead")
	var bare := VersionNotice.message("0.5.20", "0.5.21")
	_ok(bare.contains("protocol 0.5.20") and not bare.contains("build"), "builds are left out when unknown")
	_ok(VersionNotice.row_text("0.5.20", "0.5.21", "0.6.1").contains("build 0.6.1"), "server row names the server build")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	main._show_version_dialog("0.5.19")
	await get_tree().process_frame
	var d := main.menu.get_node_or_null("VersionDialog") as AcceptDialog
	_ok(d != null and d.visible, "a refused join opens the dialog")
	_ok(d != null and d.dialog_text.contains(Game.NET_VERSION) and d.dialog_text.contains("0.5.19")
		and d.dialog_text.contains(Game.build_version()), "the dialog shows ours, theirs and the build")
	print("VERSION SOURCE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
