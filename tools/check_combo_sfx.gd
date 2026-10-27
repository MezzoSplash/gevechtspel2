extends Node
## Combo SFX headless: ding per move with rising pitch, special whoosh for wall/dive moves, kaching on
## landing, record scratch on bail, all on the UI bus, rate limited.
##   godot --headless res://tools/check_combo_sfx.tscn   → "COMBO SFX CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var hud = main.get_node("CanvasLayer/Hud")
	for f in ["ding", "special", "land", "bail"]:
		var st := load("res://assets/sounds/combo_%s.wav" % f) as AudioStream
		_ok(st != null and st.get_length() > 0.1 and st.get_length() < 1.0, "combo_%s.wav loads (%.2fs)" % [f, st.get_length() if st else 0.0])
	var log: Array = hud.combo_sfx_log
	hud._on_combo_changed(30, 1.0, 3.0, "SLIDE", "build", 0)
	_ok(log.size() == 1 and log[-1][0] == "ding", "first move: ding")
	_ok(hud._combo_sfx.bus == &"UI", "on the UI bus")
	await get_tree().create_timer(0.15).timeout
	hud._on_combo_changed(70, 1.5, 3.0, "SLIDE > AIR", "build", 0)
	_ok(log.size() == 2 and log[-1][0] == "ding" and float(log[-1][1]) > float(log[0][1]), "pitch rises with the multiplier")
	hud._on_combo_changed(130, 2.0, 3.0, "SLIDE > AIR > WALLRUN", "build", 0)
	_ok(log.size() == 2, "a move right after another: no second sound (rate limit)")
	await get_tree().create_timer(0.15).timeout
	hud._on_combo_changed(210, 2.5, 3.0, "AIR > WALLRUN > WALL JUMP", "build", 0)
	_ok(log[-1][0] == "special", "wall jump: special whoosh + ching")
	var n: int = log.size()
	hud._on_combo_changed(210, 2.5, 2.0, "AIR > WALLRUN > WALL JUMP", "frozen", 0)
	_ok(log.size() == n, "a freeze update with no new points is silent")
	hud._on_combo_changed(210, 2.5, 0.0, "", "landed", 525)
	_ok(log[-1][0] == "land", "landed: kaching (even right after a move)")
	await get_tree().create_timer(0.15).timeout
	hud._on_combo_changed(30, 1.0, 3.0, "SLIDE", "build", 0)
	_ok(log[-1][0] == "ding" and is_equal_approx(float(log[-1][1]), 1.0), "new combo: pitch back to 1")
	hud._on_combo_changed(30, 1.0, 0.0, "", "bailed", 0)
	_ok(log[-1][0] == "bail", "bailed: record scratch")
	print("COMBO SFX CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)
