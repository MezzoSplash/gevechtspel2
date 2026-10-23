extends Node
## Headless: rebind swap, reset, save/load round trip, buses. Prints PASS/FAIL lines.

func _ready() -> void:
	var fails := 0
	Game.reset_bindings()
	var jump_before := Game.binding_text("jump")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	var swapped := Game.rebind("reload", ev) # Space belongs to jump
	fails += _check("swap reported", swapped == "Jump")
	fails += _check("reload is Space", Game.binding_text("reload") == jump_before)
	fails += _check("jump got R", Game.binding_text("jump") == "R")
	Game.crosshair_style = 3
	Game.set_colorblind(1)
	Game.save_settings()
	Game.crosshair_style = 0
	Game.load_settings()
	Game._bind_inputs()
	fails += _check("crosshair persisted", Game.crosshair_style == 3)
	fails += _check("colourblind persisted", Game.colorblind == 1)
	fails += _check("binding persisted", Game.binding_text("jump") == "R")
	Game.reset_bindings()
	fails += _check("reset", Game.binding_text("jump") == jump_before and Game.binding_text("crouch").contains("/"))
	for b in ["Master", "SFX", "Music", "UI"]:
		fails += _check("bus " + b, AudioServer.get_bus_index(b) != -1)
	Game.set_crosshair(0, 0, 1.0)
	Game.set_colorblind(0)
	print("SETTINGS CHECK: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(fails)


func _check(what: String, ok: bool) -> int:
	print(("  ok  " if ok else "  FAIL ") + what)
	return 0 if ok else 1
