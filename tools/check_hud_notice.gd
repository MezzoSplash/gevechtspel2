extends Node
## The notice line and the streak/flag popup, split out of hud.gd (#106). Headless, no match: the layer
## is a Control of its own, so its API can be driven directly.
##   godot --headless --path . res://tools/check_hud_notice.tscn   → "HUD NOTICE CHECK OK"
##
## What this protects: the split must keep the behaviour the HUD promises. A notice says its text while
## it is up and nothing after; a popup shows its title at the layout's top edge, and both go away when
## the layer is reset (leave to menu).
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var layer := HudNotice.new()
	add_child(layer)
	layer.setup(null) # no bottom stack in a bare check: the notice hangs off the layer
	_ok(layer.notice_text().is_empty(), "a fresh layer shows no notice")

	# 1) A notice is up while its timer runs, and gone after it.
	layer.show_notice("Class changes at next spawn", 0.15)
	_ok(layer.notice_text() == "Class changes at next spawn", "the notice carries its text while it is up")
	# 0.15 s hold + 0.5 s fade: give it both.
	await get_tree().create_timer(1.0).timeout
	_ok(layer.notice_text().is_empty(), "the notice is gone once its timer has run out")

	# 2) A second notice replaces the first instead of stacking.
	layer.show_notice("first", 5.0)
	layer.show_notice("second", 5.0)
	_ok(layer.notice_text() == "second", "a new notice replaces the one on screen")

	# 3) The popup: title, position at the layout's top edge, and it hides on demand.
	layer.show_popup("UAV", HudLayout.POPUP_FRIENDLY, "[center]by BOT 3[/center]", HudLayout.POPUP_TOP)
	_ok(layer.popup_visible() and layer.popup_title() == "UAV", "the popup shows its title")
	var box := layer.get_node_or_null("StreakPopup") as Control
	_ok(box != null and is_equal_approx(box.offset_top, HudLayout.POPUP_TOP),
		"the popup sits at HudLayout.POPUP_TOP (%s)" % (box.offset_top if box else NAN))
	_ok(is_equal_approx(box.offset_bottom - box.offset_top, HudLayout.POPUP_HEIGHT),
		"and is as tall as HudLayout.POPUP_HEIGHT")
	layer.hide_popup()
	_ok(not layer.popup_visible(), "hide_popup() takes it off screen")

	# 4) Reset (leave to menu) drops whatever is on screen, without waiting for a timer.
	layer.show_notice("still up", 30.0)
	layer.show_popup("RC-XD", HudLayout.POPUP_HOSTILE, "", HudLayout.POPUP_TOP)
	layer.reset()
	_ok(layer.notice_text().is_empty() and not layer.popup_visible(), "reset() clears both")

	layer.queue_free()
	print("HUD NOTICE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
