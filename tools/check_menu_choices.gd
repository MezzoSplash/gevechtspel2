extends Node
## Menu selection UI: map and mode are grids of chips (ChoiceRow), not dropdowns. Every option is on
## screen, exactly one chip is lit, a click on a lit chip cannot leave the row with no selection, a
## greyed-out option refuses a click, and both screens still fit the project's 1920x1080 canvas.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	await _check_behaviour()
	await _check_geometry()
	print("MENU CHOICES CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


## The real menu on main.tscn: the rows the match flow reads, plus the clicks that set them.
func _check_behaviour() -> void:
	print("-- behaviour")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.show_screen("solo")
	await get_tree().process_frame
	await get_tree().process_frame

	var maps_row: ChoiceRow = menu._map_opts[0]
	var modes_row: ChoiceRow = menu._mode_opts[0]
	_ok(maps_row.item_count == Maps.ORDER.size(), "map row lists all %d maps (%d)" % [Maps.ORDER.size(), maps_row.item_count])
	_ok(modes_row.item_count == Game.MODE_NAMES.size(), "mode row lists all %d modes (%d)" % [Game.MODE_NAMES.size(), modes_row.item_count])
	_ok(modes_row.get_item_text(0) == "TDM" and modes_row.get_item_text(Game.MODE_CTF) == "CTF", "mode chips use the short names")
	_ok(_chip(modes_row, Game.MODE_CTF).tooltip_text.contains("Capture the Flag"), "mode chip tooltip spells the full mode")

	# A real click: press the chip's signal, which is what the row listens to.
	await _click(maps_row, 2)
	_ok(menu.selected_map() == Maps.ORDER[2] and Game.last_map == Maps.ORDER[2], "clicking a map chip picks that map")
	await _click(modes_row, Game.MODE_FFA)
	_ok(menu.selected_mode() == Game.MODE_FFA, "clicking a mode chip picks that mode")
	_ok(_lit(modes_row) == 1, "exactly one mode chip is lit (%d)" % _lit(modes_row))

	# Clicking the lit chip again must not leave the row with nothing selected.
	await _click(modes_row, Game.MODE_FFA)
	_ok(modes_row.selected == Game.MODE_FFA and _lit(modes_row) == 1, "clicking the lit chip keeps it selected")
	_ok(menu.selected_mode() == Game.MODE_FFA, "and the match setting is unchanged")

	# CTF exists only on maps with flag bases: the chip is greyed out and refuses the click.
	menu.set_match_choice(&"foundry", Game.MODE_CTF)
	await get_tree().process_frame
	_ok(menu.selected_mode() == Game.MODE_TDM, "CTF on Foundry falls back to TDM")
	_ok(modes_row.is_item_disabled(Game.MODE_CTF), "CTF chip greyed out on Foundry")
	_ok(_chip(modes_row, Game.MODE_CTF).tooltip_text.contains("no flag bases"), "greyed-out chip says why")
	await _click(modes_row, Game.MODE_CTF)
	_ok(menu.selected_mode() == Game.MODE_TDM, "a disabled chip cannot be clicked into the selection")
	menu.set_match_choice(&"quay", Game.MODE_CTF)
	await get_tree().process_frame
	_ok(not modes_row.is_item_disabled(Game.MODE_CTF) and menu.selected_mode() == Game.MODE_CTF, "CTF selectable on Quay")
	main.queue_free()
	await get_tree().process_frame


## Geometry on a canvas of exactly the project's logical size: the rows are taller than the two
## dropdowns were, so the screens have to be measured instead of assumed (a headless viewport is
## 1920x1920 and would hide a vertical overflow).
func _check_geometry() -> void:
	print("-- geometry at 1920x1080")
	var canvas := Control.new()
	canvas.size = Vector2(1920, 1080)
	add_child(canvas)
	var menu: Control = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	canvas.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := Rect2(Vector2.ZERO, canvas.size)
	for screen_id in ["solo", "mp"]:
		menu.show_screen(screen_id)
		if screen_id == "mp":
			menu.set_mp_tab(0)
		await get_tree().process_frame
		await get_tree().process_frame
		var c := menu.get_node("Center/Solo" if screen_id == "solo" else "Center/Mp") as Control
		_ok(screen.encloses(c.get_global_rect()), "%s screen fits 1920x1080 (%s)" % [screen_id, c.get_global_rect()])
	var rows: Array[ChoiceRow] = [menu._map_opts[0], menu._mode_opts[0]]
	for row in rows:
		var boxes: Array[Rect2] = []
		for chip in (row.get_node("Grid") as GridContainer).get_children():
			var r := (chip as Control).get_global_rect()
			boxes.append(r)
			_ok(screen.encloses(r), "%s chip inside the canvas (%s)" % [row.name, r])
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				_ok(not boxes[i].intersects(boxes[j]), "%s chips %d and %d clear of each other" % [row.name, i, j])
		var host := row.get_parent() as Control
		_ok((row.get_node("Grid") as Control).size.x <= host.size.x + 0.5,
			"%s grid fits the menu column (%.0f <= %.0f)" % [row.name, (row.get_node("Grid") as Control).size.x, host.size.x])
	canvas.queue_free()
	await get_tree().process_frame


func _chip(row: ChoiceRow, i: int) -> Button:
	return (row.get_node("Grid") as GridContainer).get_child(i) as Button


func _click(row: ChoiceRow, i: int) -> void:
	_chip(row, i).pressed.emit()
	await get_tree().process_frame


func _lit(row: ChoiceRow) -> int:
	var n := 0
	for chip in (row.get_node("Grid") as GridContainer).get_children():
		if (chip as Button).button_pressed:
			n += 1
	return n
