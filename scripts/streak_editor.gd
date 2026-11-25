class_name StreakEditor
extends VBoxContainer
## Main menu → Killstreaks (#387), laid out as a tile grid: one tile per streak with an icon and its
## name, the focused one explained bottom-left, the three chosen slots bottom-right. The layout is
## borrowed from the classic scorestreak screen; the panels, the accent and the icons are this game's
## own, so it still looks like the rest of the menu.
##
## Choosing and removing runs through the same rules as before: StreakSelect.set_local saves and sends
## the pick, StreakDefs.sanitize validates it, and the server echoes what it accepted. A tile that would
## break a rule (a fourth pick, or a second streak on the same kill cost) stays dimmed and the info
## panel says why, so a press can never silently replace something.

signal back_pressed

const COLS := 6
const ACCENT := Color(1.0, 0.72, 0.22) # the menu theme's accent
const TEXT_DIM := Color(0.62, 0.66, 0.72)
const TEXT := Color(0.93, 0.94, 0.97)
const WARN := Color(1.0, 0.52, 0.42)

var _idle := StyleBoxFlat.new()
var _focus_box := StyleBoxFlat.new()
var _on_box := StyleBoxFlat.new()
var _tiles: Array = [] # [{id, panel, name}] in catalog order
var _grid: GridContainer
var _cursor := 0
var _pick: Array = []
var _info_name: Label
var _info_cost: Label
var _info_blurb: Label
var _info_reason: Label
var _slots: Array = [] # [{icon, name}]
var _hint: Label


func _ready() -> void:
	custom_minimum_size = Vector2(820, 0)
	add_theme_constant_override("separation", 12)
	_make_styles()
	_build()
	refresh()


## Called when the screen opens and after every change.
func refresh() -> void:
	_pick = StreakDefs.sanitize(Game.streak_choice)
	_cursor = clampi(_cursor, 0, maxi(_tiles.size() - 1, 0))
	for i in _tiles.size():
		_paint_tile(i)
	_refresh_slots()
	_show_info(_cursor)


# --- what the grid shows -----------------------------------------------------------------------

## The tile index for a streak id, -1 when the catalog has none.
func index_of(id: StringName) -> int:
	for i in _tiles.size():
		if StringName(_tiles[i].id) == id:
			return i
	return -1


func tile_count() -> int:
	return _tiles.size()


func tile_id(i: int) -> StringName:
	return StringName(_tiles[i].id) if i >= 0 and i < _tiles.size() else &""


func focused_index() -> int:
	return _cursor


func focused_id() -> StringName:
	return tile_id(_cursor)


## The slot number (1-based) of a picked streak, 0 when it is not picked.
func slot_of(id: StringName) -> int:
	for i in _pick.size():
		if StringName(_pick[i]) == id:
			return i + 1
	return 0


func picked() -> Array:
	return _pick.duplicate()


## Why this tile cannot be picked right now. Empty when it can, and empty when it is already picked:
## a press then removes it, which is always allowed.
func blocked_reason(id: StringName) -> String:
	if _pick.has(id):
		return ""
	if _pick.size() >= StreakDefs.MAX_SLOTS:
		return "%d at most: remove one first." % StreakDefs.MAX_SLOTS
	var k := StreakDefs.kills(id)
	for other in _pick:
		if StreakDefs.kills(StringName(other)) == k:
			return "Also costs %d kills, like %s: pick one of the two." % [k, StreakDefs.name_of(StringName(other))]
	return ""


# --- moving and choosing -----------------------------------------------------------------------

## Moves the focus through the grid. Returns false at an edge so the caller can leave the key alone.
func move_cursor(dx: int, dy: int) -> bool:
	var n := _tiles.size()
	if n == 0:
		return false
	var cols := maxi(_grid.columns, 1)
	var col := _cursor % cols
	var row := int(_cursor / cols)
	var next := _cursor
	if dy != 0:
		var want := (row + dy) * cols + col
		if want < 0:
			return false
		if want >= n:
			# The last row can be shorter: land on its last tile instead of refusing the move.
			if (row + dy) != int((n - 1) / cols):
				return false
			next = n - 1
		else:
			next = want
	elif dx != 0:
		var want_col := col + dx
		if want_col < 0 or want_col >= cols:
			return false
		next = _cursor + dx
		if next >= n:
			return false
	_cursor = next
	for i in _tiles.size():
		_paint_tile(i)
	_show_info(_cursor)
	return true


## Puts the focus on a tile by index: a controller jump, a check, or a jump after a re-pick.
func focus_index(i: int) -> void:
	if i < 0 or i >= _tiles.size():
		return
	_cursor = i
	for k in _tiles.size():
		_paint_tile(k)
	_show_info(_cursor)


## Enter / A, or a click on the tile.
func activate_focused() -> bool:
	return activate_index(_cursor)


func activate_index(i: int) -> bool:
	if i < 0 or i >= _tiles.size():
		return false
	var id := tile_id(i)
	var reason := blocked_reason(id)
	if reason != "":
		_info_reason.text = reason
		return false
	_toggle(id)
	return true


func back() -> void:
	back_pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_left"):
		if move_cursor(-1, 0):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if move_cursor(1, 0):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if move_cursor(0, -1):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if move_cursor(0, 1):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		activate_focused()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()


## A press puts a streak in or takes it out. A fourth pick or a double kill cost is refused with a
## reason instead of silently replacing something.
func _toggle(id: StringName) -> void:
	var next: Array = _pick.duplicate()
	if next.has(id):
		next.erase(id)
	elif next.size() >= StreakDefs.MAX_SLOTS:
		_info_reason.text = "%d at most: remove one first." % StreakDefs.MAX_SLOTS
		return
	elif _cost_taken(next, StreakDefs.kills(id)):
		_info_reason.text = "%s also costs %d kills. Two streaks on the same kill cannot be picked; choose one." % [
			StreakDefs.name_of(id), StreakDefs.kills(id)]
		return
	else:
		next.append(id)
	var saved := StreakSelect.set_local(Game, next)
	var defaulted := saved != next
	_pick = saved
	refresh()
	if defaulted:
		_info_reason.text = "Pick at least one streak: the default is back."


func _cost_taken(pick: Array, kills: int) -> bool:
	for id in pick:
		if StreakDefs.kills(StringName(id)) == kills:
			return true
	return false


# --- drawing -----------------------------------------------------------------------------------

func _make_styles() -> void:
	_idle.bg_color = Color(1, 1, 1, 0.045)
	_idle.border_color = Color(1, 1, 1, 0.12)
	_idle.set_border_width_all(1)
	_idle.set_corner_radius_all(4)
	_idle.set_content_margin_all(6)
	_focus_box.bg_color = Color(1, 1, 1, 0.1)
	_focus_box.border_color = ACCENT
	_focus_box.set_border_width_all(2)
	_focus_box.set_corner_radius_all(4)
	_focus_box.set_content_margin_all(5)
	_on_box.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.12)
	_on_box.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
	_on_box.set_border_width_all(2)
	_on_box.set_corner_radius_all(4)
	_on_box.set_content_margin_all(5)


func _paint_tile(i: int) -> void:
	if i < 0 or i >= _tiles.size():
		return
	var t: Dictionary = _tiles[i]
	var id := StringName(t.id)
	var panel: PanelContainer = t.panel
	var slot := slot_of(id)
	var blocked := blocked_reason(id) != ""
	if i == _cursor:
		panel.add_theme_stylebox_override("panel", _focus_box)
	elif slot > 0:
		panel.add_theme_stylebox_override("panel", _on_box)
	else:
		panel.add_theme_stylebox_override("panel", _idle)
	panel.modulate = Color(1, 1, 1, 0.45 if blocked else 1.0)
	var nm: Label = t.name
	nm.text = "%d · %s" % [slot, StreakDefs.name_of(id)] if slot > 0 else str(StreakDefs.name_of(id))
	nm.add_theme_color_override("font_color", ACCENT if slot > 0 else TEXT)


func _refresh_slots() -> void:
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var id := StringName(_pick[i]) if i < _pick.size() else &""
		var icon: StreakIcon = s.icon
		icon.streak_id = id
		icon.visible = id != &""
		icon.queue_redraw()
		var nm: Label = s.name
		nm.text = StreakDefs.name_of(id) if id != &"" else "—"


func _show_info(i: int) -> void:
	var id := tile_id(i)
	if id == &"":
		_info_name.text = ""
		_info_cost.text = ""
		_info_blurb.text = ""
		_info_reason.text = ""
		return
	_info_name.text = StreakDefs.name_of(id)
	_info_cost.text = "%d KILLS" % StreakDefs.kills(id)
	_info_blurb.text = StreakDefs.blurb(id)
	_info_reason.text = blocked_reason(id)


func _build() -> void:
	var title := Label.new()
	title.name = "Title"
	title.text = "KILLSTREAKS"
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)

	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	add_child(_grid)
	for d in StreakDefs.CATALOG:
		var id := StringName(d["id"])
		var panel := PanelContainer.new()
		panel.name = "Tile_%s" % String(id)
		panel.custom_minimum_size = Vector2(126, 116)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.add_theme_stylebox_override("panel", _idle)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 0)
		panel.add_child(v)
		var icon := StreakIcon.new(id)
		icon.custom_minimum_size = Vector2(64, 62)
		v.add_child(icon)
		var nm := Label.new()
		nm.text = StreakDefs.name_of(id)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.add_theme_font_size_override("font_size", 13)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nm)
		var idx := _tiles.size()
		panel.gui_input.connect(func(ev: InputEvent) -> void: _on_tile_input(idx, ev))
		panel.mouse_entered.connect(func() -> void: _hover(idx))
		_grid.add_child(panel)
		_tiles.append({"id": id, "panel": panel, "name": nm})

	var mid := HBoxContainer.new()
	mid.name = "Bottom"
	mid.add_theme_constant_override("separation", 24)
	add_child(mid)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(420, 132)
	info.add_theme_constant_override("separation", 2)
	mid.add_child(info)
	_info_name = Label.new()
	_info_name.name = "InfoName"
	_info_name.add_theme_font_size_override("font_size", 26)
	info.add_child(_info_name)
	_info_cost = Label.new()
	_info_cost.name = "InfoCost"
	_info_cost.add_theme_font_size_override("font_size", 15)
	_info_cost.add_theme_color_override("font_color", ACCENT)
	info.add_child(_info_cost)
	_info_blurb = Label.new()
	_info_blurb.name = "InfoBlurb"
	_info_blurb.add_theme_font_size_override("font_size", 14)
	_info_blurb.add_theme_color_override("font_color", TEXT_DIM)
	_info_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_info_blurb)
	_info_reason = Label.new()
	_info_reason.name = "InfoReason"
	_info_reason.add_theme_font_size_override("font_size", 13)
	_info_reason.add_theme_color_override("font_color", WARN)
	_info_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_info_reason)

	var sel := VBoxContainer.new()
	sel.name = "Selected"
	sel.add_theme_constant_override("separation", 4)
	mid.add_child(sel)
	var cap := Label.new()
	cap.name = "SelectedCaption"
	cap.text = "SELECTED KILLSTREAKS"
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", TEXT_DIM)
	sel.add_child(cap)
	var row := HBoxContainer.new()
	row.name = "SlotRow"
	row.add_theme_constant_override("separation", 6)
	sel.add_child(row)
	for i in StreakDefs.MAX_SLOTS:
		if i > 0:
			var arrow := Label.new()
			arrow.text = "▶"
			arrow.add_theme_color_override("font_color", TEXT_DIM)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)
		var sp := PanelContainer.new()
		sp.name = "Slot%d" % (i + 1)
		sp.custom_minimum_size = Vector2(84, 78)
		sp.add_theme_stylebox_override("panel", _idle)
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 0)
		sp.add_child(sv)
		var si := StreakIcon.new(&"")
		si.custom_minimum_size = Vector2(48, 44)
		sv.add_child(si)
		var sn := Label.new()
		sn.text = "—"
		sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sn.add_theme_font_size_override("font_size", 11)
		sn.add_theme_color_override("font_color", TEXT_DIM)
		sv.add_child(sn)
		row.add_child(sp)
		_slots.append({"panel": sp, "icon": si, "name": sn})

	# No hint bar here: the menu already draws the Navigate / Select / Back line at the bottom of every
	# screen, and two of them read as a bug.


func _hover(idx: int) -> void:
	_cursor = idx
	for i in _tiles.size():
		_paint_tile(i)
	_show_info(_cursor)


func _on_tile_input(idx: int, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_hover(idx)
		activate_index(idx)
