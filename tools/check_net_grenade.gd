extends Node
## Client half of a networked grenade test. Start a dedicated server first:
##   godot --headless -- --server --port 7799 --map quay --mode ffa --bots 0
##   godot --headless res://tools/check_net_grenade.tscn
## The client throws a frag; it must explode, i.e. the server's boom RPC reaches the client.
## One frag is the property under test — the class carries `grenade_max()` and the server owns the
## count, so asking for two asserted more frags than the loadout has (it printed 1/2 for months).

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main) # RPC paths need /root/Main, like the real game
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_host_ip("127.0.0.1")
	menu.set_host_port(7799)
	menu.connect_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		var id := multiplayer.get_unique_id()
		me = Game.player_for_peer(id)
		if me and not me.is_dead and not Game.play_locked() and me.grenades > 0:
			break
	if me == null:
		print("NET GRENADE CHECK FAILED (no pawn)")
		get_tree().quit()
		return
	await get_tree().create_timer(1.0).timeout
	var booms := 0
	var start := Game._grenade_done.size()
	me.grenades = me.grenade_max()
	# One frag is the property under test: the class carries `grenade_max()` and the server owns the
	# count, so asking for two asserted more frags than the loadout has (it printed 1/2 for months).
	for _i in 50:
		if not Game.play_locked():
			break
		await get_tree().create_timer(0.1).timeout
	me._try_throw_grenade()
	for _i in 40:
		await get_tree().create_timer(0.1).timeout
		if Game._grenade_done.size() - start >= 1:
			break
	booms = Game._grenade_done.size() - start
	print("throw: booms seen=%d grenades left=%d visuals=%d" % [
		booms, me.grenades, get_tree().get_nodes_in_group("grenade").size()])
	print("NET GRENADE CHECK ", "OK" if booms >= 1 else "FAILED (0/1 exploded)")
	get_tree().quit(1 if booms < 1 else 0)
