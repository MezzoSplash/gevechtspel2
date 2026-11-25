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

	await _styles()
	await _footer()
	await _layout()

	# Back leaves the screen.
	_key("ui_cancel")
	await get_tree().process_frame
	_ok(_backed == 1, "Esc asks the menu to go back")

	print("STREAK GRID CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## #387 review: focus and "picked" must be two different signals, and a tile that is both shows both.
func _styles() -> void:
	StreakSelect.set_local(Game, ["uav", "los"])
	_ed.refresh()
	_ed.focus_index(0) # focused and picked
	var both: Dictionary = _ed.tile_style(0)
	_ed.focus_index(1) # focused, not picked
	var focus_only: Dictionary = _ed.tile_style(1)
	var picked_only: Dictionary = _ed.tile_style(0)
	_ok(both.state == "focus_selected", "a picked tile with the focus says so (%s)" % both.state)
	_ok(focus_only.state == "focus" and picked_only.state == "selected", "focus and picked are told apart")
	_ok(focus_only.border.s < 0.2 and picked_only.border.s > 0.5,
		"the focus frame is white and the picked frame is the accent (%s vs %s)" % [
			focus_only.border, picked_only.border])
	_ok(int(focus_only.border_width) != int(picked_only.border_width), "and so does their weight (%d vs %d)" % [
		int(focus_only.border_width), int(picked_only.border_width)])
	# The focused frames are white (one a shade brighter than the other), the picked one is the accent,
	# so "focused and picked" carries the white frame of the focus plus the slot number of the pick.
	_ok(both.border.s < 0.12 and focus_only.border.s < 0.12 and picked_only.border.s > 0.5 and int(both.slot) > 0,
		"focused and picked keeps the focus frame and its slot")
	_ok(both.name_color == picked_only.name_color and both.name_color != Color.WHITE,
		"the picked name keeps the accent colour while focused")


## #387 review: the grid's footer names the left and right arrows; other screens keep the up/down hint.
func _footer() -> void:
	var menu := (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.show_screen("streaks")
	await get_tree().process_frame
	await get_tree().process_frame
	var f := menu.get_node("Footer") as Label
	_ok(f.text.contains("←") and f.text.contains("→"), "the killstreak footer shows left and right (%s)" % f.text)
	menu.show_screen("home")
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(not f.text.contains("←") and not f.text.contains("→"), "another screen keeps the up/down hint (%s)" % f.text)
	_ok(f.text.contains("↑") and f.text.contains("↓"), "and still shows up and down")
	menu.queue_free()
	await get_tree().process_frame


## #387 review: the title and the explanation must not run into the menu's card bar, and no two blocks
## of the screen may overlap — at 1080p, at 720p and in a smaller window.
func _layout() -> void:
	for size in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(1024, 600)]:
		(_ed.get_parent() as Control).size = size
		await get_tree().process_frame
		await get_tree().process_frame
		var tag := "%dx%d" % [int(size.x), int(size.y)]
		_ok(_ed.top_gap() >= 12.0, "%s: the title keeps clear of the card bar (%.0f px)" % [tag, _ed.top_gap()])
		var r: Dictionary = _ed.content_rects()
		var keys := ["title", "intro", "grid", "info", "selected"]
		var clashes: Array = []
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				if (r[keys[i]] as Rect2).intersects(r[keys[j]]):
					clashes.append("%s over %s" % [keys[i], keys[j]])
		var clash := ", ".join(clashes)
		_ok(clash == "", "%s: title, intro, grid, info and slots each have their own space%s" % [
			tag, "" if clash == "" else " (clash: %s)" % clash])
		var box := _ed.get_global_rect()
		var outside := ""
		for k in keys:
			if not box.encloses(r[k]):
				outside = k
		_ok(outside == "", "%s: every block stays inside the screen%s" % [tag, "" if outside == "" else " (%s)" % outside])
		var order_ok := (r.intro as Rect2).position.y >= (r.title as Rect2).end.y - 0.5
		order_ok = order_ok and (r.grid as Rect2).position.y >= (r.intro as Rect2).end.y - 0.5
		_ok(order_ok, "%s: title, then the explanation, then the grid" % tag)


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
