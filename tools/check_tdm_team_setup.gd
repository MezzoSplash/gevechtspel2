extends Node
## Team Deathmatch team setup: the host picks how many bots fight BESIDE them and how many against,
## so two humans can face ten bots. Before this, one Bots spin box filled both teams by balance and
## a friend joining trimmed the bots away.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.show_screen("solo")
	await get_tree().process_frame

	# --- menu rows: a team mode asks per side, FFA keeps the single total.
	menu.set_match_choice(&"townhouses", Game.MODE_TDM)
	await get_tree().process_frame
	_ok(_row_visible(menu, "_ally_boxes") and _row_visible(menu, "_enemy_boxes"), "TDM shows 'bots with you' and 'bots against you'")
	_ok(not _row_visible(menu, "_bot_boxes"), "TDM hides the single Bots row")
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	await get_tree().process_frame
	_ok(not _row_visible(menu, "_ally_boxes") and _row_visible(menu, "_bot_boxes"), "FFA shows the single Bots row only")

	# --- the two numbers are the match: 0 beside you, 10 against you.
	menu.set_match_choice(&"townhouses", Game.MODE_TDM)
	menu.set_team(Game.TEAM_A)
	for b in menu._ally_boxes:
		b.value = 0
	for b in menu._enemy_boxes:
		b.value = 10
	await get_tree().process_frame
	_ok(menu.selected_bot_allies() == 0 and menu.selected_bot_enemies() == 10, "0 with you, 10 against (%d/%d)" % [menu.selected_bot_allies(), menu.selected_bot_enemies()])
	_ok(menu.selected_bots() == 10, "the total follows the two sides (10)")

	menu.play_local_pressed.emit()
	await _wait_for_bots(main, 10)
	var blue := _bots_on(main, Game.TEAM_A)
	var orange := _bots_on(main, Game.TEAM_B)
	_ok(orange == 10, "ten enemy bots on Orange (%d)" % orange)
	_ok(blue == 0, "no bots on your own side (%d)" % blue)
	_ok(Game.bot_split_active() and Game.bot_target(Game.TEAM_A) == 0 and Game.bot_target(Game.TEAM_B) == 10, "the match runs the split (%d/%d)" % [Game.bot_target(Game.TEAM_A), Game.bot_target(Game.TEAM_B)])

	# --- a friend joining the same side must not trim the enemy bots away.
	main._spawn_player(2, Game.TEAM_A)
	await get_tree().process_frame
	main._trim_bots()
	main._fill_bots()
	await get_tree().process_frame
	_ok(_bots_on(main, Game.TEAM_B) == 10, "a friend joining keeps all ten enemy bots (%d)" % _bots_on(main, Game.TEAM_B))
	_ok(Game.player_for_peer(2) != null and Game.player_for_peer(2).team_id == Game.TEAM_A, "the friend is on your team")

	# --- the other side of the street: two allies, six enemies.
	menu.set_team(Game.TEAM_B)
	for b in menu._ally_boxes:
		b.value = 2
	for b in menu._enemy_boxes:
		b.value = 6
	await get_tree().process_frame
	menu.play_local_pressed.emit()
	await _wait_for_bots(main, 8)
	_ok(_bots_on(main, Game.TEAM_B) == 2, "two ally bots on Orange (%d)" % _bots_on(main, Game.TEAM_B))
	_ok(_bots_on(main, Game.TEAM_A) == 6, "six enemy bots on Blue (%d)" % _bots_on(main, Game.TEAM_A))
	_ok(Game.bot_target(Game.TEAM_B) == 2 and Game.bot_target(Game.TEAM_A) == 6, "allies follow the team you picked")

	print("TDM TEAM SETUP CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _bots_on(main: Node, team: int) -> int:
	var n := 0
	for child in main.players_root.get_children():
		var p := child as Player
		if p and p.is_bot and not p.is_queued_for_deletion() and p.team_id == team:
			n += 1
	return n


## Poll instead of one fixed wait: the pawns are spawned by the match clock, not by the button.
func _wait_for_bots(main: Node, want: int) -> void:
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		var n := 0
		for child in main.players_root.get_children():
			var p := child as Player
			if p and p.is_bot and not p.is_queued_for_deletion():
				n += 1
		if n >= want:
			return


func _row_visible(menu: Node, field: String) -> bool:
	var boxes: Array = menu.get(field)
	if boxes.is_empty():
		return false
	var row := boxes[0].get_parent() as Control
	return row.visible
