class_name StreakEditor
extends VBoxContainer
## Main menu → Killstreaks (#387). Three slots at the top, the catalog below; click a streak to put it
## in or take it out. The pick is saved in settings.cfg and sent to the server, which validates it and
## echoes the accepted list back (the HUD follows that). Two streaks with the same kill cost cannot be
## picked together: the last one you click wins nothing, and the note says why.

signal back_pressed

var _slots: Array[Button] = []
var _rows: Dictionary = {} # id -> its toggle button
var _note: Label
var _pick: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(820, 0)
	add_theme_constant_override("separation", 10)
	_build()
	refresh()


## Called when the screen opens, and after every change.
func refresh() -> void:
	_pick = StreakDefs.sanitize(Game.streak_choice)
	for i in _slots.size():
		var b := _slots[i]
		var id := StringName(_pick[i]) if i < _pick.size() else &""
		b.text = "%d. %s" % [i + 1, StreakDefs.name_of(id)] if id != &"" else "%d. —" % (i + 1)
		b.tooltip_text = StreakDefs.blurb(id) if id != &"" else "Leeg: kies een killstreak uit de lijst"
	for id in _rows:
		var b := _rows[id] as Button
		var on := _pick.has(id)
		b.set_pressed_no_signal(on)
		b.text = "HAAL WEG" if on else "KIES"
		b.disabled = not on and _pick.size() >= StreakDefs.MAX_SLOTS
		b.tooltip_text = "Maximaal %d gekozen" % StreakDefs.MAX_SLOTS if b.disabled else ""
	_note.text = "Gekozen: %d van %d. Kills zonder dood tellen; dood gaan zet de teller terug." % [
		_pick.size(), StreakDefs.MAX_SLOTS]


## A click puts a streak in or takes it out. A fourth pick or a double kill cost is refused with a
## message instead of silently replacing something.
func _toggle(id: StringName) -> void:
	var next: Array = _pick.duplicate()
	if next.has(id):
		next.erase(id)
	elif next.size() >= StreakDefs.MAX_SLOTS:
		_note.text = "Maximaal %d: haal er eerst een weg." % StreakDefs.MAX_SLOTS
		return
	elif _cost_taken(next, StreakDefs.kills(id)):
		_note.text = "%s kost ook %d kills. Twee met dezelfde drempel kan niet; kies er één." % [
			StreakDefs.name_of(id), StreakDefs.kills(id)]
		return
	else:
		next.append(id)
	var saved := StreakSelect.set_local(Game, next)
	if saved != next:
		_note.text = "Die keuze kan niet; de standaard staat weer aan."
	_pick = saved
	refresh()


func _cost_taken(pick: Array, kills: int) -> bool:
	for id in pick:
		if StreakDefs.kills(StringName(id)) == kills:
			return true
	return false


func _build() -> void:
	var title := Label.new()
	title.text = "KILLSTREAKS"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var tag := Label.new()
	tag.text = "Kies maximaal drie. Een reeks telt kills zonder dood; dood gaan zet de teller terug."
	tag.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	tag.add_theme_font_size_override("font_size", 15)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tag)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	add_child(slots)
	for i in StreakDefs.MAX_SLOTS:
		var b := Button.new()
		b.name = "Slot%d" % (i + 1)
		b.custom_minimum_size = Vector2(240, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE # a readout, not a control
		slots.add_child(b)
		_slots.append(b)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	add_child(list)
	for d in StreakDefs.CATALOG:
		var id := StringName(d["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		row.add_child(text)
		var name_label := Label.new()
		name_label.text = "%s · %d kills" % [StreakDefs.name_of(id), StreakDefs.kills(id)]
		name_label.add_theme_font_size_override("font_size", 16)
		text.add_child(name_label)
		var blurb_label := Label.new()
		blurb_label.text = StreakDefs.blurb(id)
		blurb_label.add_theme_font_size_override("font_size", 12)
		blurb_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
		blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(blurb_label)
		var b := Button.new()
		b.name = "Toggle_%s" % String(id)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 40)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void: _toggle(id))
		row.add_child(b)
		_rows[id] = b

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 36)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)
