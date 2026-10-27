extends Node
## Join tab + server query. Start a server first:
##   godot --headless -- --server --port 7799 --map quay --mode ffa --bots 4
##   godot --headless res://tools/check_server_list.tscn
var _fails := 0

func _ok(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		_fails += 1

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.show_screen("mp")
	menu.set_mp_tab(1)
	_ok(menu.get_node("Center/Mp/JoinRow").visible and not menu.get_node("Center/Mp/HostButton").visible, "join tab hides host controls")
	menu.set_mp_tab(0)
	_ok(menu.get_node("Center/Mp/HostButton").visible and not menu.get_node("Center/Mp/JoinRow").visible, "host tab hides join controls")
	var got := {}
	Game.server_query.server_info.connect(func(a: String, info: Dictionary, ping: int, lan: bool) -> void:
		got[("lan " if lan else "") + a] = [info, ping]
	)
	Game.server_query.query("127.0.0.1:7799")
	Game.server_query.query("localhost:7799")
	Game.server_query.scan_lan(7799)
	await get_tree().create_timer(1.5).timeout
	print("replies: ", got)
	_ok(got.has("127.0.0.1:7799"), "direct query answered")
	_ok(got.has("localhost:7799"), "hostname query answered")
	var any_lan := false
	for k in got:
		if str(k).begins_with("lan "):
			any_lan = true
	_ok(any_lan, "LAN broadcast answered")
	if got.has("127.0.0.1:7799"):
		var info: Dictionary = got["127.0.0.1:7799"][0]
		_ok(info.get("map") == "Quay" and int(info.get("bots")) == 4 and int(info.get("players")) == 0, "map Quay, 4 bots, 0 players")
	var saved_last := Game.last_server
	Game.set_last_server("10.1.2.3:7001")
	menu._prefill_last_server()
	_ok(menu.host_ip() == "10.1.2.3" and menu.host_port() == 7001, "last server prefilled")
	Game.set_last_server(saved_last)
	print("SERVER LIST CHECK ", "OK" if _fails == 0 else "FAILED (%d)" % _fails)
	get_tree().quit()
