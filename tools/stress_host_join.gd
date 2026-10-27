extends Node
## Listen-host via the menu (TDM Quay) + clients that join, play and rejoin. Prints STRESS lines.
##   host:   godot --headless res://tools/stress_host_join.tscn -- --host --secs 240
##   client: godot --headless res://tools/stress_host_join.tscn -- --join --secs 240 --rejoin 40
func _arg(n: String, d: float) -> float:
	var a := OS.get_cmdline_user_args()
	var i := a.find(n)
	return float(a[i + 1]) if i >= 0 and i + 1 < a.size() else d

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	var secs := _arg("--secs", 240.0)
	var t0 := Time.get_ticks_msec()
	if a.has("--host"):
		Game.bot_count = 6
		menu.set_match_choice(&"quay", Game.MODE_TDM)
		menu.set_host_port(7801)
		menu.host_pressed.emit()
		await get_tree().create_timer(12.0).timeout
		menu.start_match_pressed.emit()
		print("STRESS host started match, lobby=%s" % Game.in_lobby)
		while Time.get_ticks_msec() - t0 < secs * 1000.0:
			await get_tree().create_timer(10.0).timeout
			print("STRESS host t=%d pawns=%d peers=%s" % [(Time.get_ticks_msec() - t0) / 1000, main.players_root.get_child_count(), multiplayer.get_peers()])
	else:
		var rejoin := _arg("--rejoin", 0.0)
		while Time.get_ticks_msec() - t0 < secs * 1000.0:
			menu.set_host_ip("127.0.0.1")
			menu.set_host_port(7801)
			menu.connect_pressed.emit()
			var stay := rejoin if rejoin > 0.0 else secs
			var t1 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t1 < stay * 1000.0 and Time.get_ticks_msec() - t0 < secs * 1000.0:
				await get_tree().create_timer(5.0).timeout
				print("STRESS client t=%d pawns=%d hud=%s" % [(Time.get_ticks_msec() - t0) / 1000, main.players_root.get_child_count(), main.hud.visible])
			if rejoin > 0.0:
				main._leave_to_menu()
				print("STRESS client left")
				await get_tree().create_timer(2.0).timeout
	print("STRESS DONE")
	get_tree().quit()
