extends Node
## #106-split guard: renaming yourself still reaches the roster now that the logic lives in
## `Lobby.push_live_name`. Offline, so `Game` is its own authority and no RPC goes out.
##   godot --headless --path . res://tools/check_live_name.tscn   → "LIVE NAME CHECK OK"
##
## What this protects: the split out of game.gd (audio buses, match config, live name) must not change
## behaviour. A rename has to clean the string, persist it, update the scoreboard row and tell the menu.
var fails := 0
var _seen: Array[String] = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	Game.is_dedicated = false
	Game.in_lobby = false
	Game.player_name = "Player"
	Game.profile_name = "Player"
	Game.scores.clear()
	var spy := func(n: String) -> void: _seen.append(n)
	Game.local_name_changed.connect(spy)

	# 1) Trimming and the signal.
	Game.set_player_name("  Gianni  ")
	_ok(Game.player_name == "Gianni", "the name is trimmed (%s)" % Game.player_name)
	_ok(Game.profile_name == "Gianni", "the profile name follows, so it survives a restart")
	_ok(_seen.size() == 1 and _seen[0] == "Gianni", "local_name_changed fired once, with the new name")

	# 2) The same name again is not a change.
	Game.set_player_name("Gianni")
	_ok(_seen.size() == 1, "an unchanged name does not fire the signal again")

	# 3) One line only: a newline or a tab becomes a space, control characters are dropped.
	Game.set_player_name("a\nb\tc")
	_ok(not Game.player_name.contains("\n") and not Game.player_name.contains("\t"),
		"a name never carries a newline or a tab (%s)" % Game.player_name)

	# 4) The roster row follows the name, without a pawn (the menu case).
	Game.scores[1] = {"name": "old", "kills": 0, "team": 0, "style": 0, "deaths": 0}
	Game.set_player_name("Roster")
	_ok(str(Game.scores[1].get("name", "")) == "Roster",
		"the scoreboard row for our own peer is renamed (%s)" % Game.scores[1].get("name", ""))

	# 5) Empty falls back instead of leaving a blank row on the board.
	Game.set_player_name("   ")
	_ok(Game.player_name == "Player", "an empty name falls back to Player (%s)" % Game.player_name)

	Game.local_name_changed.disconnect(spy)
	print("LIVE NAME CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)