extends Node
## #387 tile grid: drives the real screen the way a player does — arrow keys and Enter pushed through
## the viewport, a click through the tile's own input — and checks what the grid and the pick do.
##   godot --headless --path . res://tools/check_streak_grid.tscn
var fails := 0
var _ed: StreakEditor
var _backed := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	Game.streak_choice = []
	var frame := Control.new()
	frame.size = Vector2(1280, 720)
	add_child(frame)
	_ed = StreakEditor.new()
	_ed.name = "Killstreaks"
	frame.add_child(_ed)
	await get_tree().process_frame
	_ed.back_pressed.connect(func() -> void: _backed += 1)

	# Start from a single pick so the grid has room to be filled and blocked in turn.
	StreakSelect.set_local(Game, ["uav"])
	_ed.refresh()
	await get_tree().process_frame

	_ok(_ed.tile_count() == StreakDefs.CATALOG.size(), "a tile per streak in the catalog (%d)" % _ed.tile_count())
	_ok(_ed.focused_index() == 0 and _ed.focused_id() == &"uav", "the first tile starts focused")
	_ok(_ed._info_name.text == "UAV" and _ed._info_cost.text == "3 KILLS", "the info panel shows UAV and its cost")
	_ok(_ed.slot_of(&"uav") == 1, "the pick from settings shows in slot 1")

	# Arrows: right moves one tile, left back, and the edges refuse instead of wrapping.
	_key("ui_right")
	await get_tree().process_frame
	_ok(_ed.focused_index() == 1 and _ed.focused_id() == &"rcxd", "the right arrow moves to RCXplodie")
	_ok(_ed._info_name.text == "RCXplodie", "the info panel follows the focus")
	_key("ui_left")
	await get_tree().process_frame
	_ok(_ed.focused_index() == 0, "the left arrow moves back")
	_ok(not _ed.move_cursor(-1, 0), "the left edge does not wrap")
	_ok(not _ed.move_cursor(0, -1), "the top edge does not wrap")

	# Enter picks the focused tile; the tile and the slots panel show it.
	_ed.focus_index(2) # LOS
	_key("ui_accept")
	await get_tree().process_frame
	_ok(_ed.picked().has(&"los") and _ed.slot_of(&"los") > 0, "Enter picks the focused streak")
	_ok(_ed._tiles[2].name.text.begins_with("%d · " % _ed.slot_of(&"los")),
		"the tile shows its slot number (%s)" % _ed._tiles[2].name.text)

	# A third pick fills the row; the fourth tile is dimmed and says why.
	_ed.focus_index(1)
	_key("ui_accept")
	await get_tree().process_frame
	_ok(_ed.picked().size() == StreakDefs.MAX_SLOTS, "three picks fill the slots")
	_ed.focus_index(3) # Overdrive
	await get_tree().process_frame
	_ok(_ed.blocked_reason(&"overdrive") != "", "a fourth tile reports a reason")
	_ok(not _ed.activate_index(3), "and cannot be picked")
	_ok(_ed.picked().size() == StreakDefs.MAX_SLOTS, "the pick is unchanged")
	_ok(is_equal_approx(_ed._tiles[3].panel.modulate.a, 0.45), "the full tile is dimmed")

	# The 7-kill collision: Overdrive stays blocked while LOS is picked, and both stay separable.
	_ed.focus_index(0)
	_key("ui_accept") # remove UAV, back to RCXplodie + LOS
	await get_tree().process_frame
	_ok(_ed.picked().size() == 2 and not _ed.picked().has(&"uav"), "a second press removes the streak")
	_ed.focus_index(3)
	await get_tree().process_frame
	var reason := _ed.blocked_reason(&"overdrive")
	_ok(reason.contains("7") and reason.contains("LOS"), "Overdrive is blocked by LOS on the same 7 kills (%s)" % reason)
	_ok(not _ed.activate_index(3) and not _ed.picked().has(&"overdrive"), "and cannot be picked")
	_ok(_ed._info_reason.text != "", "the info panel shows the reason")

	# Drop LOS and Overdrive becomes available: the collision is the only thing in the way.
	_ed.focus_index(2)
	_key("ui_accept")
	await get_tree().process_frame
	_ed.focus_index(3)
	await get_tree().process_frame
	_ok(_ed.blocked_reason(&"overdrive") == "", "with LOS gone Overdrive can be picked")
	_ok(_ed.activate_index(3) and _ed.picked().has(&"overdrive"), "and picking it works")

	# Slots are ordered by kill cost, whatever order they were picked in.
	var costs: Array = []
	for id in _ed.picked():
		costs.append(StreakDefs.kills(StringName(id)))
	var sorted := costs.duplicate()
	sorted.sort()
	_ok(costs == sorted, "the slots run in kill order (%s)" % str(costs))

	# A click on a tile goes through the same door as Enter.
	var before := _ed.picked().size()
	_click(0)
	await get_tree().process_frame
	_ok(_ed.picked().size() != before or _ed.picked().has(&"uav"), "a click on a tile toggles it")

	# Back leaves the screen.
	_key("ui_cancel")
	await get_tree().process_frame
	_ok(_backed == 1, "Esc asks the menu to go back")

	print("STREAK GRID CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	get_viewport().push_input(up)


func _click(idx: int) -> void:
	var panel: PanelContainer = _ed._tiles[idx].panel
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	panel.gui_input.emit(ev)
