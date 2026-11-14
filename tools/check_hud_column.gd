extends SceneTree
## The top-centre HUD column has one source of truth (`shared/hud_layout.gd`) and the scene has to agree
## with it: the match clock is drawn by `scenes/hud.tscn`, so its numbers are the one place the layout
## table cannot reach. This reads the scene as text and fails when the two drift apart, or when the
## stack starts to overlap.
##   godot --headless --path . -s res://tools/check_hud_column.gd   → "HUD COLUMN CHECK OK"
##
## Why a text check: the offsets are scene data, and no runtime assertion can tell "the clock is where
## HudLayout says" apart from "the clock happened to render fine at this resolution". The stack itself
## is also rendered by tools/check_hud_layout (real Control positions at three resolutions); this check
## guards the numbers the scene and the table both carry.
const SRC := "res://scenes/hud.tscn"
const LAYOUT := "res://shared/hud_layout.gd"


func _initialize() -> void:
	quit(1 if _run() > 0 else 0)


func _node_block(src: String, node: String) -> String:
	var at := src.find('[node name="%s"' % node)
	if at < 0:
		return ""
	var end := src.find("\n[node ", at + 1)
	return src.substr(at, (end - at) if end > at else -1)


func _offset(block: String, key: String) -> float:
	for line in block.split("\n"):
		if line.begins_with(key + " = "):
			return float(line.split("=")[1].strip_edges())
	return NAN


func _run() -> int:
	var fails := 0
	var scene := FileAccess.get_file_as_string(SRC)
	var layout := FileAccess.get_file_as_string(LAYOUT)
	if scene.is_empty() or layout.is_empty():
		print("  FAIL cannot read %s / %s" % [SRC, LAYOUT])
		print("HUD COLUMN CHECK FAILED (1 failures)")
		return 1

	# The clock is the one node the layout table cannot own, so the scene has to match it.
	var timer := _node_block(scene, "Timer")
	var top := _offset(timer, "offset_top")
	var bottom := _offset(timer, "offset_bottom")
	fails += _ok(not timer.is_empty() and is_equal_approx(top, HudLayout.CLOCK_TOP),
		"the scene's clock starts at HudLayout.CLOCK_TOP (%.0f)" % top)
	fails += _ok(is_equal_approx(bottom, HudLayout.CLOCK_BOTTOM),
		"the scene's clock ends at HudLayout.CLOCK_BOTTOM (%.0f)" % bottom)

	# The stack: clock, then the standing/CTF line, then the popup. No row starts before the one above ends.
	fails += _ok(HudLayout.CLOCK_BOTTOM <= HudLayout.STANDING_TOP + 0.5,
		"the standing line starts under the clock (%.0f >= %.0f)" % [HudLayout.STANDING_TOP, HudLayout.CLOCK_BOTTOM])
	fails += _ok(HudLayout.STANDING_BOTTOM <= HudLayout.POPUP_TOP + 0.5,
		"the popup starts under the standing line (%.0f >= %.0f)" % [HudLayout.POPUP_TOP, HudLayout.STANDING_BOTTOM])
	fails += _ok(HudLayout.CLOCK_BOTTOM <= HudLayout.CTF_TOP + 0.5,
		"the CTF block starts under the clock (%.0f >= %.0f)" % [HudLayout.CTF_TOP, HudLayout.CLOCK_BOTTOM])
	fails += _ok(HudLayout.CTF_TOP + HudLayout.CTF_HEIGHT + HudLayout.POPUP_GAP >= HudLayout.POPUP_TOP,
		"the CTF popup sits below the CTF block (%.0f >= %.0f)"
			% [HudLayout.CTF_TOP + HudLayout.CTF_HEIGHT + HudLayout.POPUP_GAP, HudLayout.POPUP_TOP])

	# hud.gd must not keep its own copy of these numbers: the aliases point at the table.
	var hud := FileAccess.get_file_as_string("res://scripts/hud.gd")
	for name in ["POPUP_TOP", "POPUP_HEIGHT", "CTF_STATUS_TOP", "CTF_STATUS_H", "HUD_ACCENT", "HUD_PANEL"]:
		var line := ""
		for l in hud.split("\n"):
			if l.begins_with("const %s :=" % name):
				line = l
		fails += _ok(line.contains("HudLayout."),
			"%s is the layout table's value, not a second copy" % name)

	print("HUD COLUMN CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	return fails


func _ok(c: bool, msg: String) -> int:
	if c:
		print("  PASS %s" % msg)
		return 0
	print("  FAIL %s" % msg)
	return 1
