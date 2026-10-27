extends Node
## Headless: deaths/K/D rows, round reset, recent servers save/load + menu dropdown. PASS/FAIL lines.

func _ready() -> void:
	var fails := 0
	Game.scores.clear()
	Game.register_participant(-1, "Bot 1", 0)
	Game.register_participant(-2, "Bot 2", 1)
	Game._add_death(-2)
	Game._add_death(-2)
	var rows := Game.get_scores()
	var d2 := 0
	for r in rows:
		if int(r.peer_id) == -2:
			d2 = int(r.deaths)
	fails += _check("deaths counted", d2 == 2)
	Game.sync_all_scores(rows)
	fails += _check("deaths survive full sync", int(Game.scores[-2].deaths) == 2)
	fails += _check("NET_VERSION bumped", Game.NET_VERSION == "0.3.13-dev")
	var keep := Game.recent_servers
	Game.recent_servers = PackedStringArray()
	for i in 7:
		Game.remember_server("10.0.0.%d" % i, 7777)
	Game.remember_server("10.0.0.3", 7777)
	fails += _check("recent capped", Game.recent_servers.size() == Game.RECENT_SERVERS_MAX)
	fails += _check("recent newest first, deduped", Game.recent_servers[0] == "10.0.0.3:7777" and Game.recent_servers.count("10.0.0.3:7777") == 1)
	Game.load_settings()
	fails += _check("recent round trip", Game.recent_servers.size() == Game.RECENT_SERVERS_MAX and Game.recent_servers[0] == "10.0.0.3:7777")
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var pick: OptionButton = menu.find_child("RecentServers", true, false)
	fails += _check("menu dropdown", pick != null and pick.item_count == Game.RECENT_SERVERS_MAX + 1)
	if pick:
		menu._on_recent_picked(1)
		fails += _check("pick fills ip/port", menu.host_ip() == "10.0.0.3" and menu.host_port() == 7777)
	Game.recent_servers = keep
	Game.save_settings()
	print("DONE fails=%d" % fails)
	get_tree().quit(fails)


func _check(what: String, ok: bool) -> int:
	print(("PASS " if ok else "FAIL ") + what)
	return 0 if ok else 1
