extends Node
## The saved resolution is the player's pick: with a 1080p primary and a 1440p second monitor, a
## 2560x1440 pick used to be clamped to the monitor the window started on and saved as 1920x1080
## on every launch. It is now only replaced when no monitor can show it; the window itself is
## still fitted to the monitor it is on.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var small := Vector2i(1920, 1080)
	var big := Vector2i(2560, 1440)
	var screens: Array[Vector2i] = [small, big]
	var largest := GameSettings.largest_of(screens)
	_ok(largest == big, "the largest of a 1080p and a 1440p monitor is the 1440p one")
	_ok(GameSettings.largest_of([] as Array[Vector2i]) == Vector2i.ZERO, "no monitors, no size")
	var pick := Vector2i(2560, 1440)
	_ok(GameSettings.clamp_window_size(Game, pick, largest) == pick, "a 1440p pick is kept when one monitor can show it")
	_ok(GameSettings.clamp_window_size(Game, pick, small) == small, "the window is still fitted to a 1080p monitor it starts on")
	_ok(GameSettings.clamp_window_size(Game, Vector2i(3840, 2160), largest) == big, "a pick no monitor can show is replaced by the largest that fits")
	print("WINDOW PICK CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
