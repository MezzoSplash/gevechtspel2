extends Node
## HudBoard, TrickPopup and StandingLine (scripts/hud/, split out of hud.gd in #315): the round end opens
## the board with its cards for ROUND_END_SHOW and closes it after, unless Tab is held; Tab opens and
## closes it; leaving the match hides the cards; the board sorts on the mode's score; a trick shows its
## word with the combo and hides again; the FFA line names your place. Driven through the real HUD.
##   godot --headless res://tools/check_hud_board.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	Game.scores.clear()
	Game.scores[1] = {"name": "Me", "kills": 7, "team": 0, "style": 90, "deaths": 2}
	Game.scores[-1] = {"name": "Bot", "kills": 9, "team": 0, "style": 0, "deaths": 4}
	var hud: Hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	hud.set_process(false)
	hud._local_peer_id = 1
	await get_tree().process_frame
	var b := hud.board

	var rows := Game.get_scores()
	rows.sort_custom(HudBoard.sort_scores)
	_ok(str(rows[0].name) == "Bot", "FFA kills: the leader sorts first")

	b.tick(0.016, true)
	_ok(b.open and hud.scoreboard_container.visible, "Tab opens the board")
	b.tick(0.016, false)
	_ok(not b.open and not hud.scoreboard_container.visible, "letting go of Tab closes it")

	hud._on_round_ended(1, "Me", {})
	_ok(b.open and b.winner.visible and (b.winner.get_node("V/Name") as Label).text == "YOU WIN", "round end: the board opens with the winner card")
	_ok(hud.style_king_text().contains("ME"), "round end: the style king names the style leader")
	b.tick(HudBoard.ROUND_END_SHOW - 0.5, false)
	_ok(b.open and b.winner.visible, "the round end holds the board without Tab")
	b.tick(1.0, false)
	_ok(not b.open and not b.winner.visible, "and closes it after ROUND_END_SHOW")
	hud._on_round_ended(1, "Me", {})
	b.tick(HudBoard.ROUND_END_SHOW + 0.1, true)
	_ok(b.open and not b.winner.visible, "Tab held at the end keeps the board, the cards go")
	hud._on_killcam_finished()
	_ok(b.winner.visible and b.round_end_timer > 0.0, "the final killcam brings the round end back")
	hud.reset_session()
	_ok(not b.winner.visible and b.round_end_winner == "", "leaving the match clears the round end")

	hud.show_trick("AIRSHOT", 150, 1.5)
	_ok(hud.trick_text() == "AIRSHOT!" and hud.trick.sub.text.contains("x1.5 COMBO"), "a trick shows its word and combo")
	hud._hide_trick()
	_ok(hud.trick_text() == "", "and hides again")

	hud._local_peer_id = 1 # reset_session dropped it
	hud._refresh_standing()
	var st := hud._standing
	_ok(st != null and st.visible and st.text.begins_with("2nd"), "FFA: the line names your place (%s)" % (st.text if st else ""))
	_ok(StandingLine.ordinal(11) == "11th" and StandingLine.ordinal(22) == "22nd", "ordinals: 11th, 22nd")

	hud.queue_free()
	Game.scores.clear()
	Game.mode = Game.MODE_TDM
	print("HUD BOARD CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
