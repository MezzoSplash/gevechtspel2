extends Node
## #64: after you die you get the killer's damage to you and yours to them.
##   offline: godot --headless res://tools/check_death_report.tscn
##   online:  start `godot --headless -- --server --port 7799 --map quay --mode ffa --bots 8`, then
##            godot --headless res://tools/check_death_report.tscn -- --net
func _ready() -> void:
	var net := OS.get_cmdline_user_args().has("--net")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	if net:
		menu.set_host_ip("127.0.0.1")
		menu.set_host_port(7799)
		menu.connect_pressed.emit()
	else:
		Game.bot_count = 8
		menu.set_match_choice(&"quay", Game.MODE_FFA)
		menu.play_local_pressed.emit()
	var hud = main.get_node("CanvasLayer/Hud")
	for i in 1200:
		await get_tree().create_timer(0.1).timeout
		var me := Game.player_for_peer(multiplayer.get_unique_id())
		if me and not me.is_dead and i % 20 == 0:
			me.global_position += Vector3(0, 0.01, 0) # stand still in the open; bots find us
		if hud._death_report and hud._death_report.visible:
			var v = hud._death_report.get_node("V")
			print("report: %s | %s | %s | %s" % [v.get_node("Head").text, v.get_node("Weapon").text, v.get_node("Taken/R").text, v.get_node("Dealt/R").text])
			var taken := int(str(v.get_node("Taken/R").text).split(" ")[0])
			print("DEATH REPORT CHECK ", "OK" if taken >= 100 and str(v.get_node("Weapon").text).begins_with("with ") else "FAILED (taken %d)" % taken)
			get_tree().quit()
			return
	print("DEATH REPORT CHECK FAILED (never died / no report)")
	get_tree().quit()
