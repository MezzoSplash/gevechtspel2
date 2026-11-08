class_name ChoiceRow
extends VBoxContainer
## One match setting with every option on screen: a gold caption and a grid of toggle buttons.
## Replaces the OptionButton the menu used for map and mode - a dropdown hid the choices, its
## popup still looked like the early builds, and the current value was easy to miss.
##
## It keeps the small slice of the OptionButton API the menu already used (add_item, select,
## selected, item_count, item_selected, set_item_disabled, is_item_disabled, set_item_tooltip),
## so the match rows and their checks did not have to care which control sat behind it.

signal item_selected(index: int)

const CHIP_HEIGHT := 32.0

var selected := 0

var item_count: int:
	get:
		return _buttons.size()

var _caption: Label
var _grid: GridContainer
var _buttons: Array[Button] = []
var _hints: Array[String] = []
var _group := ButtonGroup.new()
var _quiet := false


## `columns` is how many chips share a row; the grid grows downwards.
func setup(caption: String, columns: int) -> void:
	name = caption.to_pascal_case()
	_group.allow_unpress = true # so select() can clear the old chip; a click is pushed back below
	_caption = Label.new()
	_caption.text = caption.to_upper()
	_caption.theme_type_variation = &"SectionLabel"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = maxi(columns, 1)
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(_grid)
	add_theme_constant_override("separation", 4)


func add_item(label: String, hint: String = "") -> void:
	var idx := _buttons.size()
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_group = _group
	b.theme_type_variation = &"ChoiceChip"
	b.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	b.tooltip_text = hint
	b.pressed.connect(func() -> void: _pick(idx))
	_grid.add_child(b)
	_buttons.append(b)
	_hints.append(hint)
	if idx == 0:
		b.set_pressed_no_signal(true)


## Move the selection without emitting item_selected (the menu mirrors two of these rows).
func select(i: int) -> void:
	if _buttons.is_empty():
		return
	i = clampi(i, 0, _buttons.size() - 1)
	selected = i
	_quiet = true
	for k in _buttons.size():
		_buttons[k].set_pressed_no_signal(k == i)
	_quiet = false


func set_item_disabled(i: int, on: bool) -> void:
	if i < 0 or i >= _buttons.size():
		return
	_buttons[i].disabled = on
	if on and _buttons[i].tooltip_text.strip_edges() == "":
		_buttons[i].tooltip_text = "Not available here."


func is_item_disabled(i: int) -> bool:
	return i >= 0 and i < _buttons.size() and _buttons[i].disabled


func set_item_tooltip(i: int, text: String) -> void:
	if i < 0 or i >= _buttons.size():
		return
	# A note (why an option is greyed out) is added under the option's own explanation; an empty note
	# restores that explanation. Never blank the chip's tooltip: it is the only place that says what
	# "CTF" or "Style FFA" means.
	var base := _hints[i]
	_buttons[i].tooltip_text = base if text.strip_edges() == "" else "%s\n%s" % [base, text]


func get_item_text(i: int) -> String:
	return _buttons[i].text if i >= 0 and i < _buttons.size() else ""


## The player clicked a chip. A toggle can be clicked off again; the row always keeps one selection,
## so the click is answered by re-pressing the chip it landed on.
func _pick(idx: int) -> void:
	if _quiet or idx < 0 or idx >= _buttons.size() or _buttons[idx].disabled:
		return
	selected = idx
	_buttons[idx].set_pressed_no_signal(true)
	item_selected.emit(idx)
