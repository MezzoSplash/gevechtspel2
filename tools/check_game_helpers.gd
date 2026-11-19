extends Node
## The Game entry points that #316 slice 1 moved into Lobby, GameSettings and BotProfiles still do what
## they did: the server list (recent + favourites), the menu's remembered match, the colourblind clamp,
## bot difficulty parsing and profiles, and the lobby/chat RPC bodies on an offline server (the sender
## of a local call is the server itself). settings.cfg is put back as it was.
##   godot --headless res://tools/check_game_helpers.tscn
var fails := 0
const CFG := "user://settings.cfg"


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var had := FileAccess.file_exists(CFG)
	var saved := FileAccess.get_file_as_string(CFG) if had else ""
	var recent := Game.recent_servers
	var favs := Game.favorite_servers
	var last := Game.last_server

	Game.recent_servers = PackedStringArray()
	for i in Game.RECENT_SERVERS_MAX + 2:
		Game.remember_server(" 10.0.0.%d " % i, 7777)
	_ok(Game.recent_servers.size() == Game.RECENT_SERVERS_MAX, "recent servers are capped")
	_ok(Game.recent_servers[0] == "10.0.0.%d:7777" % (Game.RECENT_SERVERS_MAX + 1) and Game.last_server == Game.recent_servers[0], "the newest is first and becomes the last server")
	Game.remember_server("10.0.0.3", 7777)
	_ok(Game.recent_servers[0] == "10.0.0.3:7777" and Game.recent_servers.count("10.0.0.3:7777") == 1, "joining one again moves it to the front, once")

	Game.favorite_servers = PackedStringArray()
	_ok(Game.add_favorite("Home", " 1.2.3.4:7777 "), "a favourite is added")
	_ok(not Game.add_favorite("Again", "1.2.3.4:7777") and not Game.add_favorite("Empty", "  "), "no duplicate address, no empty address")
	_ok(Game.favorite_servers == PackedStringArray(["Home|1.2.3.4:7777"]), "stored as label|address")
	Game.remove_favorite("1.2.3.4:7777")
	_ok(Game.favorite_servers.is_empty(), "removed by address")

	Game.remember_match_choice(&"foundry", Game.MODE_FFA, 999, 0, 99, 7, 3, 4)
	_ok(Game.last_map == &"foundry" and Game.last_mode == Game.MODE_FFA, "map and mode remembered")
	_ok(Game.last_kills == Game.KILLS_MAX and Game.last_time_min == Game.TIME_MIN_MINUTES and Game.last_bots == Game.BOT_COUNT_MAX,
		"kills, time and bots are clamped")
	_ok(Game.last_bot_difficulty == Game.BOT_HARD and Game.bot_difficulty == Game.BOT_HARD, "skill is clamped and applied")
	_ok(Game.last_bot_allies == 3 and Game.last_bot_enemies == 4, "the per-side bots are kept")

	Game.set_colorblind(99)
	_ok(Game.colorblind == Game.COLORBLIND_NAMES.size() - 1, "colourblind is clamped")
	Game.set_colorblind(0)

	_ok(Game.parse_bot_difficulty(" Normal ") == Game.BOT_MEDIUM and Game.parse_bot_difficulty("h") == Game.BOT_HARD
		and Game.parse_bot_difficulty("x") == -1, "difficulty names parse, unknown is -1")
	Game.bot_difficulty = 99
	_ok(Game.bot_profile() == Game.BOT_PROFILES[Game.BOT_HARD] and Game.BOT_PROFILES == BotProfiles.PROFILES,
		"the profile is clamped and the table has one source")
	Game.bot_difficulty = Game.BOT_MEDIUM

	# Offline server: a local call is the server's own peer (1).
	var lines: Array = []
	var on_line := func(n: String, _team: int, text: String) -> void: lines.append([n, text])
	Game.chat_message.connect(on_line)
	Game.submit_chat("   ")
	Game.submit_chat("  hoi  ")
	Game.submit_chat("x".repeat(Game.CHAT_MAX + 30))
	Game.chat_message.disconnect(on_line)
	_ok(lines.size() == 2 and lines[0][1] == "hoi" and str(lines[1][1]).length() == Game.CHAT_MAX,
		"chat: empty dropped, trimmed, cut to CHAT_MAX (%d lines)" % lines.size())

	var was_lobby := Game.in_lobby
	Game.in_lobby = true
	Game.lobby[1] = {"name": "Host", "team": Game.TEAM_A}
	Game.request_lobby_team(7)
	_ok(int(Game.lobby[1].team) == Game.TEAM_B and int(Game.pending_teams[1]) == Game.TEAM_B, "lobby team is clamped and pending")
	Game.submit_display_name("  Neo  ", Game.TEAM_A)
	_ok(str(Game.lobby[1].name) == "Neo" and int(Game.lobby[1].team) == Game.TEAM_A, "in the lobby a name and side land on its row")
	Game.lobby.erase(1)
	Game.pending_names.erase(1)
	Game.pending_teams.erase(1)
	Game.in_lobby = was_lobby

	Game.recent_servers = recent
	Game.favorite_servers = favs
	Game.last_server = last
	if had:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_string(saved)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	print("GAME HELPERS CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
