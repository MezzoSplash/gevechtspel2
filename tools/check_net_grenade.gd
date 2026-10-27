extends Node
## Client half of a networked grenade test. Start a dedicated server first:
##   godot --headless -- --server --port 7799 --map quay --mode ffa --bots 0
##   godot --headless res://tools/check_net_grenade.tscn
## The client throws three frags; each must explode (server boom RPC reaches the client).

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
	me.grenades = 3
	for k in 2:
		me._try_throw_grenade()
		await get_tree().create_timer(2.5).timeout
		booms = Game._grenade_done.size() - start
		print("throw %d: booms seen=%d grenades left=%d visuals=%d" % [k + 1, booms, me.grenades, get_tree().get_nodes_in_group("grenade").size()])
	print("NET GRENADE CHECK ", "OK" if booms >= 2 else "FAILED (%d/2 exploded)" % booms)
	get_tree().quit()
