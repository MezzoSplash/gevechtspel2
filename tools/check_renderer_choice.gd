extends Node
## Graphics > Renderer: the choice exists, maps to a real Godot rendering method, and the relaunch
## that applies it can never fire on a dedicated server, headless, from the editor, or twice in a row
## (the second one would be a boot loop).
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	_ok(Game.RENDERER_NAMES.size() == Game.RENDERER_IDS.size(), "one method id per name (%d / %d)" % [Game.RENDERER_NAMES.size(), Game.RENDERER_IDS.size()])
	_ok(Game.RENDERER_IDS[0] == "", "Auto has no override")
	_ok(Game.RENDERER_IDS[1] == "forward_plus" and Game.RENDERER_IDS[2] == "mobile" and Game.RENDERER_IDS[3] == "gl_compatibility", "the three Godot rendering methods, spelled as Godot wants them")

	var none := PackedStringArray()
	var marked := PackedStringArray([Game.RENDERER_MARKER])
	_ok(not Game.should_relaunch(0, none, false, false, false), "Auto never relaunches")
	_ok(Game.should_relaunch(2, none, false, false, false), "a real choice relaunches a normal windowed game")
	_ok(not Game.should_relaunch(2, none, true, false, false), "never on a dedicated server (systemd would loop)")
	_ok(not Game.should_relaunch(2, none, false, true, false), "never headless")
	_ok(not Game.should_relaunch(2, none, false, false, true), "never from the editor")
	_ok(not Game.should_relaunch(2, marked, false, false, false), "the relaunched process does not relaunch again")
	_ok(not Game.should_relaunch(99, none, false, false, false), "an out-of-range choice is ignored")
	_ok(not Game.should_relaunch(-1, none, false, false, false), "a negative choice is ignored")

	# The setter clamps; it writes settings.cfg, so put the old value back afterwards.
	var before := Game.renderer_choice
	Game.set_renderer_choice(99)
	_ok(Game.renderer_choice == Game.RENDERER_NAMES.size() - 1, "the setter clamps to the last renderer")
	Game.set_renderer_choice(-4)
	_ok(Game.renderer_choice == 0, "and to the first")
	Game.renderer_choice = before

	print("RENDERER CHOICE CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
