class_name ClassEditor
extends VBoxContainer
## Main menu → Classes. List on the left (New / Delete), the selected class on the right.
## Every edit is saved at once to user://classes.cfg (Game.loadouts.save).

signal back_pressed

var _list: ItemList
var _new_btn: Button
var _del_btn: Button
var _name_edit: LineEdit
var _primary: OptionButton
var _secondary: OptionButton
var _spins: Dictionary = {} # grenade type → SpinBox
var _total: Label
var _sel := 0
var _loading := false


func _ready() -> void:
	custom_minimum_size = Vector2(820, 0)
	add_theme_constant_override("separation", 12)
	_build()
	refresh()


## Called when the screen opens: the file may have changed since.
func refresh(select: int = -1) -> void:
	var classes := Game.loadouts.classes
	if select >= 0:
		_sel = select
	_sel = clampi(_sel, 0, classes.size() - 1)
	_list.clear()
	for c in classes:
		_list.add_item(_item_text(c))
	if classes.size() > 0:
		_list.select(_sel)
	_new_btn.disabled = not Game.loadouts.can_add()
	_new_btn.tooltip_text = "Up to %d classes" % PlayerClasses.MAX_CLASSES
	_del_btn.disabled = classes.size() <= 1
	_load_fields()


func selected_index() -> int:
	return _sel


func _load_fields() -> void:
	var classes := Game.loadouts.classes
	if classes.is_empty():
		return
	_loading = true
	var c: Dictionary = classes[_sel]
	if _name_edit.text != str(c.name):
		_name_edit.text = c.name
	_primary.select(PlayerClasses.PRIMARIES.find(StringName(c.primary)))
	_secondary.select(PlayerClasses.SECONDARIES.find(StringName(c.secondary)))
	for t in _spins:
		(_spins[t] as SpinBox).value = int((c.grenades as Dictionary).get(String(t), 0))
	_loading = false
	_update_total()


## Reads the widgets into a class and saves it. Grenade totals above the cap are trimmed by sanitize.
func _commit() -> void:
	if _loading:
		return
	var g := {}
	for t in _spins:
		g[String(t)] = int((_spins[t] as SpinBox).value)
	var c := {
		"name": _name_edit.text,
		"primary": String(PlayerClasses.PRIMARIES[maxi(_primary.selected, 0)]),
		"secondary": String(PlayerClasses.SECONDARIES[maxi(_secondary.selected, 0)]),
		"grenades": g,
	}
	Game.loadouts.update_class(_sel, c)
	var saved: Dictionary = Game.loadouts.classes[_sel]
	_list.set_item_text(_sel, _item_text(saved))
	_update_total()


## Typing: list follows live; the field itself is cleaned when you leave it (so spaces can be typed).
func _on_name_changed(_t: String) -> void:
	_commit()


func _on_name_done() -> void:
	_load_fields()


## Mix and match: a spin box can go only as high as the room the others leave.
func _on_grenade_changed(_v: float, changed: StringName) -> void:
	if _loading:
		return
	var others := 0
	for t in _spins:
		if t != changed:
			others += int((_spins[t] as SpinBox).value)
	var spin := _spins[changed] as SpinBox
	var room := PlayerClasses.MAX_GRENADES - others
	if spin.value > room:
		_loading = true
		spin.value = room
		_loading = false
	_commit()


func _item_text(c: Dictionary) -> String:
	return "%s  —  %s" % [c.name, PlayerClasses.summary(c)]


func _update_total() -> void:
	var total := 0
	for t in _spins:
		total += int((_spins[t] as SpinBox).value)
	_total.text = "Grenades %d / %d" % [total, PlayerClasses.MAX_GRENADES]


func _on_new() -> void:
	var i := Game.loadouts.add_class()
	if i >= 0:
		refresh(i)
		_name_edit.grab_focus()
		_name_edit.select_all()


func _on_delete() -> void:
	if Game.loadouts.delete_class(_sel):
		refresh(maxi(_sel - 1, 0))


func _build() -> void:
	var title := Label.new()
	title.text = "CLASSES"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var tag := Label.new()
	tag.text = "What you spawn with. Pick one when a match starts; change it from the Esc menu."
	tag.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	tag.add_theme_font_size_override("font_size", 15)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tag)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 300)
	_list.add_theme_font_size_override("font_size", 16)
	_list.item_selected.connect(func(i: int) -> void:
		_sel = i
		_load_fields()
	)
	left.add_child(_list)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	left.add_child(btns)
	_new_btn = Button.new()
	_new_btn.text = "New class"
	_new_btn.custom_minimum_size = Vector2(0, 36)
	_new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_btn.pressed.connect(_on_new)
	btns.add_child(_new_btn)
	_del_btn = Button.new()
	_del_btn.text = "Delete"
	_del_btn.custom_minimum_size = Vector2(0, 36)
	_del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_del_btn.pressed.connect(_on_delete)
	btns.add_child(_del_btn)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	_name_edit = LineEdit.new()
	_name_edit.max_length = PlayerClasses.NAME_MAX
	_name_edit.placeholder_text = "Class name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_name_done())
	_name_edit.focus_exited.connect(_on_name_done)
	right.add_child(_field("Name", _name_edit))
	_primary = OptionButton.new()
	for id in PlayerClasses.PRIMARIES:
		_primary.add_item(PlayerClasses.weapon_label(id))
	_primary.item_selected.connect(func(_i: int) -> void: _commit())
	right.add_child(_field("Primary", _primary))
	_secondary = OptionButton.new()
	for id in PlayerClasses.SECONDARIES:
		_secondary.add_item(PlayerClasses.weapon_label(id))
	_secondary.item_selected.connect(func(_i: int) -> void: _commit())
	right.add_child(_field("Secondary", _secondary))
	for t in PlayerClasses.GRENADE_TYPES:
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = PlayerClasses.MAX_GRENADES
		spin.step = 1
		spin.rounded = true
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var gt: StringName = t
		spin.value_changed.connect(func(v: float) -> void: _on_grenade_changed(v, gt))
		_spins[t] = spin
		right.add_child(_field("%s grenades" % PlayerClasses.GRENADE_NAMES.get(t, String(t).capitalize()), spin))
	_total = Label.new()
	_total.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_total)
	var note := Label.new()
	note.text = "Max %d classes · %d grenades in total" % [PlayerClasses.MAX_CLASSES, PlayerClasses.MAX_GRENADES]
	note.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
	note.add_theme_font_size_override("font_size", 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(note)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 36)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)


func _field(label_text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(130, 0)
	h.add_child(l)
	h.add_child(control)
	return h
