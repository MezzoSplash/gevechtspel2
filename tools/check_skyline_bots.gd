extends Node
## Solo match on Skyline with bots for ~60 s: logs bot heights and how they died.
##   godot --headless res://tools/check_skyline_bots.tscn

var _deaths := {}
var _falls := 0

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 8
	Game.bot_count = 8
	menu.set_match_choice(&"skyline", Game.MODE_TDM)
	menu.play_local_pressed.emit()
	Game.kill_feed.connect(func(_k: String, _v: String, weapon_id: StringName, _a = null, _b = null, _c = null, _d = null) -> void:
		_deaths[weapon_id] = int(_deaths.get(weapon_id, 0)) + 1
	)
	var levels := {}
	for t in 12:
		await get_tree().create_timer(5.0).timeout
		var ys: PackedStringArray = []
		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Player
			if p and p.is_bot and not p.is_dead:
				ys.append("%.0f" % p.global_position.y)
				levels[snappedf(p.global_position.y, 1.0)] = true
		print("t=%2ds map=%s bot y: %s" % [(t + 1) * 5, Game.map_id, ", ".join(ys)])
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and p.is_bot and not p.is_dead:
			p.global_position = Vector3(0, -8, 33) # the street gap between spawn and tower
			break
	await get_tree().create_timer(0.5).timeout
	print("fall kill zone: ", "ok" if _deaths.has(&"fall") else "FAIL")
	var lv := levels.keys()
	lv.sort()
	print("heights visited: ", lv)
	print("deaths by weapon: ", _deaths)
	get_tree().quit()
