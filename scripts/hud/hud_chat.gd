class_name HudChat
extends RefCounted
## Chat and presence (part of the HUD): the chat box (T opens, Enter sends, Esc closes without
## unlocking the cursor), the chat log (newest at the bottom, eight lines, fading after 8 s) and the
## join/leave feed above it (newest on top, five rows). The HUD owns the nodes from its scene and the
## key handling; this holds what happens to them.

const LOG_MAX := 8
const LOG_HOLD := 8.0 # s before a chat line fades
const PRESENCE_MAX := 5
const PRESENCE_HOLD := 4.5 # s before a join/leave row fades
const _JOIN := Color(0.55, 0.92, 0.62, 0.95)
const _LEAVE := Color(0.92, 0.55, 0.5, 0.95)

var log: VBoxContainer
var input: LineEdit
var presence: VBoxContainer
## (name: String, team: int) -> Color: the HUD's team/FFA-aware name colour.
var name_color: Callable


func _init(log_box: VBoxContainer, input_box: LineEdit, presence_box: VBoxContainer, colour: Callable) -> void:
	log = log_box
	input = input_box
	presence = presence_box
	name_color = colour
	if input:
		input.visible = false
		input.text_submitted.connect(_on_submit)
		input.gui_input.connect(_on_gui_input)


## Player text must not become BBCode ([img], [font_size], …). [lb] is a literal "[".
static func bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


## Deferred focus so the T that opened chat is not typed into the box. Old lines light up again.
func open() -> void:
	Game.chat_open = true
	if input:
		input.visible = true
		input.text = ""
		input.call_deferred("grab_focus")
	if log:
		for c in log.get_children():
			(c as CanvasItem).modulate.a = 1.0


func close(send: bool) -> void:
	if send and input:
		Game.send_chat(input.text)
	Game.chat_open = false
	if input:
		input.release_focus()
		input.text = ""
		input.visible = false


func _on_submit(text: String) -> void:
	Game.send_chat(text)
	close(false)


func _on_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_mouse"):
		close(false)
		input.get_viewport().set_input_as_handled()


## Newest at the bottom. Name uses team colour; lines fade after LOG_HOLD.
func add_message(n: String, team: int, text: String) -> void:
	if log == null:
		return
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = name_color.call(n, team)
	row.text = "[color=#%s]%s[/color]  %s" % [col.to_html(false), bb_escape(n), bb_escape(text)]
	log.add_child(row)
	while log.get_child_count() > LOG_MAX:
		var old := log.get_child(0)
		log.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(LOG_HOLD)
	tw.tween_property(row, "modulate:a", 0.0, 0.5)


## Newest row on top: "X joined (Team)" in green, "X left" in red.
func add_presence(player_name: String, joined: bool, team: int) -> void:
	if presence == null:
		return
	var row := Label.new()
	var team_n: String = Game.TEAM_NAMES[clampi(team, 0, 1)]
	if joined and Game.is_ffa():
		row.text = "%s joined" % player_name
		row.add_theme_color_override("font_color", _JOIN)
	elif joined:
		row.text = "%s joined  (%s)" % [player_name, team_n]
		row.add_theme_color_override("font_color", _JOIN)
	else:
		row.text = "%s left" % player_name
		row.add_theme_color_override("font_color", _LEAVE)
	row.add_theme_font_size_override("font_size", 16)
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	row.add_theme_constant_override("outline_size", 4)
	presence.add_child(row)
	presence.move_child(row, 0)
	while presence.get_child_count() > PRESENCE_MAX:
		var old := presence.get_child(presence.get_child_count() - 1)
		presence.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(PRESENCE_HOLD)
	tw.tween_property(row, "modulate:a", 0.0, 0.4)
	tw.tween_callback(row.queue_free)
