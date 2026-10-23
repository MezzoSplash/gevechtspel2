extends Node
## Solo match on Skyline: drops a bot under kill_y and checks the kill feed row uses icon_fall.svg.
## Under xvfb-run it also saves /tmp/fall_icon.png (the kill feed corner).

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	Game.bot_count = 4
	main.get_node("CanvasLayer/Menu").set_match_choice(&"skyline", Game.MODE_TDM)
	main.get_node("CanvasLayer/Menu").play_local_pressed.emit()
	await get_tree().create_timer(8.0).timeout # past the round freeze and spawn protection
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and p.is_bot and not p.is_dead:
			p.global_position = Vector3(0, -8, 33)
			break
	await get_tree().create_timer(0.5).timeout
	var hud = main.hud
	var found := false
	for row in hud.kill_feed.get_children():
		for c in row.get_children():
			if c is TextureRect and (c as TextureRect).texture and (c as TextureRect).texture.resource_path.ends_with("icon_fall.svg"):
				found = true
	print("FALL ICON CHECK: %s" % ("PASS" if found else "FAIL"))
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var row := hud.kill_feed.get_child(0) as Control
		var r := Rect2i(row.get_global_rect()).grow(14)
		for c in row.get_children():
			r = r.merge(Rect2i((c as Control).get_global_rect()).grow(14))
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var crop := img.get_region(r)
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
		crop.save_png("/tmp/fall_icon.png")
		print("saved /tmp/fall_icon.png ", r)
	get_tree().quit(0 if found else 1)
