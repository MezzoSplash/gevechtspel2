extends Node
## Host tab map/mode pickers must stick and be what hosting uses (Solo picker is _map_opts[0]).
##   godot --headless res://tools/check_host_map.tscn
func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	var fails := 0
	var host: OptionButton = menu._map_opts[menu._map_opts.size() - 1]
	var host_mode: OptionButton = menu._mode_opts[menu._mode_opts.size() - 1]
	for i in Maps.ORDER.size():
		host.select(i)
		host.item_selected.emit(i)
		var ok: bool = host.selected == i and menu.selected_map() == Maps.ORDER[i] and Game.last_map == Maps.ORDER[i]
		print("%s map %s" % ["PASS" if ok else "FAIL", Maps.ORDER[i]])
		fails += 0 if ok else 1
	for m in [Game.MODE_FFA, Game.MODE_TDM]:
		host_mode.select(m)
		host_mode.item_selected.emit(m)
		var ok: bool = host_mode.selected == m and menu.selected_mode() == m
		print("%s mode %d" % ["PASS" if ok else "FAIL", m])
		fails += 0 if ok else 1
	print("HOST MAP CHECK ", "OK" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit()
