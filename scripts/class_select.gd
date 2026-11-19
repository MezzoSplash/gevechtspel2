class_name ClassSelect
extends Control
## In-game class picker. Two ways in:
## - start of a match (first spawn of the session): 10 s countdown, then the last used class is picked;
## - Esc → Change class: no countdown, the pick waits for the next spawn (Back returns to the pause menu).
## While open it counts as a menu (Game.pause_open): no look, move-input, fire or weapon keys.

signal picked(index: int, queued: bool)
signal back_pressed

const AUTO_TIME := 10.0
## Width of the first class shard; each next one is STEP narrower (CrystalUi.stagger).
const WIDE := 560.0
const STEP := 22.0
const HINT_GAP := 64.0

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
	_hint.text = "1–%d  or  click  to pick" % Game.loadouts.classes.size()
	if not initial:
		_hint.text += "   ·   esc  back"
	_hint.text = _hint.text.to_upper()
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
	var sb := _sub.get_theme_stylebox("normal") as CrystalStyle
	if initial:
		_sub.text = "AUTO-PICK IN %d S  ·  %s" % [ceili(time_left), Game.loadouts.class_name_at(Game.loadouts.auto_index()).to_upper()]
		# The seam runs out with the clock; red (danger) only in the last 3 s.
		var late := time_left <= 3.0
		sb.seam_side = CrystalStyle.Side.BOTTOM
		sb.seam_lit = time_left / AUTO_TIME
		sb.seam_color = CrystalUi.DANGER if late else CrystalStyle.ICE
		_sub.add_theme_color_override("font_color", CrystalUi.DANGER.lightened(0.25) if late else ScoreboardView.TEXT)
	else:
		_sub.text = "APPLIES AT YOUR NEXT SPAWN"
		sb.seam_side = CrystalStyle.Side.NONE
		_sub.add_theme_color_override("font_color", ScoreboardView.TEXT)


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
	var widths := []
	for i in classes.size():
		var c: Dictionary = classes[i]
		var queued := i == Game.loadouts.queued_index
		var b := Button.new()
		b.name = "Class%d" % (i + 1)
		b.theme_type_variation = &"MenuButtonBig"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 50
		b.text = "%d    %s" % [i + 1, str(c.name).to_upper()]
		var hint := PlayerClasses.summary(c)
		if queued:
			hint = "NEXT SPAWN  ·  " + hint
		CrystalUi.button_hint(b, hint.to_upper())
		if queued:
			_mark_queued(b)
		var idx := i
		b.pressed.connect(func() -> void: _pick(idx))
		_list.add_child(b)
		_buttons.append(b)
		widths.append(WIDE - i * STEP)
	CrystalUi.stagger(_buttons, widths, true)
	# A long loadout ("SMG · REVOLVER · 1 FRAG · 2 KNIVES") must not run into the name: a shard is at
	# least name + hint + a gap wide, and the column stays staggered from there.
	var floor_w := 0.0
	for b in _buttons:
		var hint := b.get_node("Hint") as Label
		floor_w = maxf(floor_w, b.get_minimum_size().x + hint.get_minimum_size().x + HINT_GAP)
	var grow := maxf(floor_w - (WIDE - (_buttons.size() - 1) * STEP), 0.0)
	for b in _buttons:
		b.custom_minimum_size.x += grow


## The class waiting for the next spawn: pale shell with its seam lit even when idle, so it reads
## as chosen next to the smoke rows (the theme's hover shard, kept for every state).
func _mark_queued(b: Button) -> void:
	var pale := b.get_theme_stylebox("hover", &"MenuButtonBig")
	if pale != null:
		b.add_theme_stylebox_override("normal", pale)
	b.add_theme_color_override("font_color", ScoreboardView.DARK)
	var hint := b.get_node_or_null("Hint") as Label
	if hint:
		hint.add_theme_color_override("font_color", Color(ScoreboardView.DARK, 0.6))


func _build() -> void:
	# Built in code, so it does not inherit the menu theme from a scene: take the crystal one.
	theme = CrystalTheme.install()
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.04, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	# No card: a centred column of floating shards, like the pause menu.
	var box := VBoxContainer.new()
	box.name = "Column"
	box.custom_minimum_size = Vector2(WIDE, 0)
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	_title = CrystalUi.caption("", 14, CrystalStyle.ICE)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = CrystalUi.caption("", 16, ScoreboardView.TEXT)
	_sub.name = "Countdown"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sub.custom_minimum_size = Vector2(360, 0)
	_sub.add_theme_stylebox_override("normal", CrystalUi.shard(Vector4(10, 10, 12, 12), 5, false,
			CrystalStyle.Side.NONE, CrystalStyle.ICE, 1.0, Vector2(22, 8)))
	box.add_child(_sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_list)
	_back = Button.new()
	_back.name = "Back"
	_back.theme_type_variation = &"PrimaryButton"
	_back.text = "‹  BACK"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.custom_minimum_size = Vector2(160, 44)
	_back.pressed.connect(_go_back)
	box.add_child(_back)
	# The key hints sit under the column, not at the screen's foot: that is where the HUD's weapon
	# slots are while a match runs behind this.
	_hint = Label.new()
	_hint.name = "Footer"
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_hint)
	CrystalUi.footer(_hint)
