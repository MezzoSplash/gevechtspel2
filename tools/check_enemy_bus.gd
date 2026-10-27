extends Node
## #59: enemy pawns use the Enemies bus (send SFX, default louder); teammates stay on SFX.
##   godot --headless res://tools/check_enemy_bus.tscn
func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.bot_count = 6
	Game.last_bots = 6
	menu.set_match_choice(&"quay", Game.MODE_TDM)
	menu.play_local_pressed.emit()
	await get_tree().create_timer(3.0).timeout
	var f := 0
	var idx := AudioServer.get_bus_index("Enemies")
	if idx < 0 or AudioServer.get_bus_send(idx) != &"SFX":
		f += 1
		print("  FAIL bus missing or not sent to SFX")
	elif not Game.enemies_vol > 1.0 or AudioServer.get_bus_volume_db(idx) < 1.0:
		f += 1
		print("  FAIL default not louder (%.1f dB)" % AudioServer.get_bus_volume_db(idx))
	var me := Game.player_for_peer(multiplayer.get_unique_id())
	var en := 0
	var mates := 0
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p == me:
			continue
		var bus := String((p.get_node("StepSfx") as AudioStreamPlayer3D).bus)
		var fire := String((p.get_node("Head/Camera3D/WeaponRoot/FireSfx") as AudioStreamPlayer3D).bus)
		var want := "Enemies" if Game.is_enemy(me, p) else "SFX"
		if bus != want or fire != want:
			f += 1
			print("  FAIL %s on %s/%s, want %s" % [p.name, bus, fire, want])
		if want == "Enemies": en += 1
		else: mates += 1
	print("enemies=%d mates=%d enemies bus %.1f dB" % [en, mates, AudioServer.get_bus_volume_db(idx)])
	print("ENEMY BUS CHECK ", "OK" if f == 0 and en > 0 and mates > 0 else "FAILED")
	get_tree().quit()
