extends Node
## HudChat (scripts/hud/hud_chat.gd, split out of hud.gd): open/close drives Game.chat_open, player
## text cannot become BBCode, the log keeps the newest LOG_MAX lines at the bottom, the presence feed
## the newest PRESENCE_MAX rows on top, and a name takes the colour the HUD hands it.
##   godot --headless res://tools/check_hud_chat.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var log := VBoxContainer.new()
	var input := LineEdit.new()
	var presence := VBoxContainer.new()
	for n in [log, input, presence]:
		add_child(n)
	var chat := HudChat.new(log, input, presence, func(n: String, _t: int) -> Color:
		return Color.RED if n == "Red" else Color.WHITE)
	_ok(not input.visible, "the input starts hidden")
	chat.open()
	_ok(Game.chat_open and input.visible, "open: chat_open and the box shows")
	input.text = "half typed"
	chat.close(false)
	_ok(not Game.chat_open and not input.visible and input.text == "", "close: box hidden and emptied")

	_ok(HudChat.bb_escape("[img]x[/img]") == "[lb]img]x[lb]/img]", "player text cannot open a BBCode tag")
	chat.add_message("Red", 1, "[font_size=90]big")
	var row := log.get_child(0) as RichTextLabel
	_ok(row.text.begins_with("[color=#%s]Red[/color]" % Color.RED.to_html(false)), "the name takes the HUD's colour")
	_ok(row.get_parsed_text() == "Red  [font_size=90]big", "a tag in the message shows as text")
	for i in HudChat.LOG_MAX + 3:
		chat.add_message("P", 0, "line %d" % i)
	_ok(log.get_child_count() <= HudChat.LOG_MAX + 1, "the log is capped (%d rows, queued frees aside)" % log.get_child_count())
	var last := log.get_child(log.get_child_count() - 1) as RichTextLabel
	_ok(last.get_parsed_text().ends_with("line %d" % (HudChat.LOG_MAX + 2)), "the newest line is at the bottom")

	for i in HudChat.PRESENCE_MAX + 2:
		chat.add_presence("Joiner %d" % i, true, 0)
	chat.add_presence("Leaver", false, 1)
	_ok(presence.get_child_count() <= HudChat.PRESENCE_MAX + 1, "the presence feed is capped")
	var top := presence.get_child(0) as Label
	_ok(top.text == "Leaver left", "the newest presence row is on top")

	print("HUD CHAT CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
