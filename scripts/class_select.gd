class_name ClassSelect
extends Control
## In-game class picker. Two ways in:
## - start of a match (first spawn of the session): 10 s countdown, then the last used class is picked;
## - Esc → Change class: no countdown, the pick waits for the next spawn (Back returns to the pause menu).
## While open it counts as a menu (Game.pause_open): no look, move-input, fire or weapon keys.

signal picked(index: int, queued: bool)
signal back_pressed

const AUTO_TIME := 10.0

var initial := false
var time_left := 0.0
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _hint: Label
var _back: Button
var _buttons: Array[Button] = []
var _open_seq := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func open_initial() -> void:
	initial = true
	time_left = AUTO_TIME
	_show()


func open_change() -> void:
	initial = false
	time_left = 0.0
	_show()


func is_open() -> bool:
	return visible


## Leave to menu / session end: no pick, no notice.
func close_silently() -> void:
	_hide()
	Game.pause_open = false


func _show() -> void:
	_open_seq += 1
	_title.text = "CHOOSE CLASS" if initial else "CHANGE CLASS"
	_back.visible = not initial
	_hint.text = "Click or press 1–%d" % Game.loadouts.classes.size()
	if not initial:
		_hint.text += "  ·  Esc to go back"
	_rebuild()
	_refresh_sub()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Game.pause_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var focus := Game.loadouts.queued_index if Game.loadouts.queued_index >= 0 else Game.loadouts.auto_index()
	if focus >= 0 and focus < _buttons.size():
		_buttons[focus].grab_focus()


func _hide() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_viewport() and get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()


func _process(delta: float) -> void:
	if not visible or not initial:
		return
	time_left = maxf(time_left - delta, 0.0)
	_refresh_sub()
	if time_left <= 0.0:
		_pick(Game.loadouts.auto_index())


func _refresh_sub() -> void:
	if initial:
		_sub.text = "Auto-pick in %d s: %s" % [ceili(time_left), Game.loadouts.class_name_at(Game.loadouts.auto_index())]
		_sub.add_theme_color_override("font_color", Color(1, 0.92, 0.55) if time_left > 3.0 else Color(1, 0.55, 0.4))
	else:
		_sub.text = "Applies at your next spawn"
		_sub.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var i := int(key.keycode - KEY_1)
		if i < Game.loadouts.classes.size():
			_pick(i)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_mouse") or event.is_action_pressed("ui_cancel"):
		if not initial:
			_go_back()
		get_viewport().set_input_as_handled()


func _pick(i: int) -> void:
	if not visible:
		return
	var queued := Game.loadouts.choose(i)
	_hide()
	picked.emit(i, queued)
	_release_input_later()


func _go_back() -> void:
	_hide()
	Game.pause_open = false
	back_pressed.emit()


## The key or click that picked must not also switch weapons / fire this frame: weapon.gd polls
## Input.is_action_just_pressed, which ignores "handled". So the menu block lasts two more frames.
func _release_input_later() -> void:
	var seq := _open_seq
	await get_tree().process_frame
	await get_tree().process_frame
	if seq == _open_seq and not visible:
		Game.pause_open = false


func _rebuild() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	var classes := Game.loadouts.classes
	for i in classes.size():
		var c: Dictionary = classes[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		var tag := ""
		if i == Game.loadouts.queued_index:
			tag = "   (next spawn)"
		b.text = "  %d   %s   —   %s%s" % [i + 1, c.name, PlayerClasses.summary(c), tag]
		var idx := i
		b.pressed.connect(func() -> void: _pick(idx))
		_list.add_child(b)
		_buttons.append(b)


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.04, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 18)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(0, 36)
	_back.pressed.connect(_go_back)
	box.add_child(_back)
