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
var _info: Label
var _presets: Array[Button] = []
## Grenade-slot presets: [frags, knives] (always the full slot).
const PRESETS := [[3, 0], [2, 1], [1, 2], [0, 3]]
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
	_update_info()


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
	_update_info()


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


## "FRAG  FRAG  KNIFE   3 / 3": one word per slot, empty slots as dashes.
func _update_total() -> void:
	var total := 0
	var cells: PackedStringArray = []
	for t in PlayerClasses.GRENADE_TYPES:
		var n := int((_spins[t] as SpinBox).value) if _spins.has(t) else 0
		total += n
		for i in n:
			cells.append(String(PlayerClasses.GRENADE_NAMES.get(t, t)).to_upper())
	while cells.size() < PlayerClasses.MAX_GRENADES:
		cells.append("—")
	_total.text = "%s     %d / %d" % ["  ·  ".join(cells), total, PlayerClasses.MAX_GRENADES]
	var frags := int((_spins[&"frag"] as SpinBox).value) if _spins.has(&"frag") else 0
	var knives := int((_spins[&"knife"] as SpinBox).value) if _spins.has(&"knife") else 0
	for i in _presets.size():
		var p: Array = PRESETS[i]
		_presets[i].button_pressed = frags == int(p[0]) and knives == int(p[1])


func _apply_preset(i: int) -> void:
	var p: Array = PRESETS[i]
	_loading = true
	(_spins[&"frag"] as SpinBox).value = int(p[0])
	(_spins[&"knife"] as SpinBox).value = int(p[1])
	_loading = false
	_commit()


## Short stat line for the two guns, so a pick is not blind.
func _update_info() -> void:
	if _info == null:
		return
	var lines: PackedStringArray = []
	for id in [
		PlayerClasses.PRIMARIES[maxi(_primary.selected, 0)], PlayerClasses.SECONDARIES[maxi(_secondary.selected, 0)]
	]:
		lines.append(weapon_blurb(id))
	_info.text = "\n".join(lines)


static func weapon_blurb(id: StringName) -> String:
	var d := Game.weapon_def(id)
	if d == null:
		return ""
	var dmg := "%d×%d" % [roundi(d.damage), d.pellet_count] if d.pellet_count > 1 else "%d" % roundi(d.damage)
	var extra := ""
	match id:
		&"smg":
			extra = " · moves 8% faster · iron sights (RMB)"
		&"revolver":
			extra = " · 2 body / 1 head"
		&"sniper":
			extra = " · scope (RMB)"
	return "%s: %s dmg · %d rpm · %d rounds · %.1fs reload%s" % [
		d.display_name, dmg, roundi(d.fire_rate * 60.0), d.mag_size, d.reload_time, extra
	]


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
	_info = Label.new()
	_info.add_theme_color_override("font_color", Color(0.66, 0.70, 0.76))
	_info.add_theme_font_size_override("font_size", 13)
	right.add_child(_info)
	var slot_title := Label.new()
	slot_title.text = "GRENADE SLOT  ·  %d throwables, any mix" % PlayerClasses.MAX_GRENADES
	slot_title.add_theme_font_size_override("font_size", 15)
	slot_title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	right.add_child(slot_title)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for i in PRESETS.size():
		var p: Array = PRESETS[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = _preset_text(int(p[0]), int(p[1]))
		var idx := i
		b.pressed.connect(func() -> void: _apply_preset(idx))
		presets.add_child(b)
		_presets.append(b)
	right.add_child(presets)
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
		right.add_child(_field(str(PlayerClasses.GRENADE_LABELS.get(t, String(t).capitalize())), spin, 170))
	_total = Label.new()
	_total.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_total)
	var note := Label.new()
	note.text = "Max %d classes · G throws a frag, F a knife (one hit kills)" % PlayerClasses.MAX_CLASSES
	note.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
	note.add_theme_font_size_override("font_size", 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(note)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 36)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)


static func _preset_text(frags: int, knives: int) -> String:
	if knives == 0:
		return "%d Frags" % frags
	if frags == 0:
		return "%d Knives" % knives
	return "%d Frag%s + %d %s" % [frags, "s" if frags > 1 else "", knives, "Knives" if knives > 1 else "Knife"]


func _field(label_text: String, control: Control, label_w: float = 130.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(label_w, 0)
	h.add_child(l)
	h.add_child(control)
	return h
