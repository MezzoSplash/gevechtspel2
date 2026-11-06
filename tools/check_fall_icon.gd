extends Node
## Solo match on Skyline: drops a bot under kill_y and checks the kill feed row uses icon_fall.svg.
## Under xvfb-run it also saves /tmp/fall_icon.png (the kill feed corner).
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	Game.bot_count = 4
	main.get_node("CanvasLayer/Menu").set_match_choice(&"skyline", Game.MODE_TDM)
	main.get_node("CanvasLayer/Menu").play_local_pressed.emit()
	# Wait for a real round instead of for a stopwatch: under load the "Get ready" freeze outlasts 8 s
	# and there is no living bot yet to drop (that is exactly how this check used to go red).
	var p: Player = null
	for i in 250: # up to 25 s
		await get_tree().create_timer(0.1).timeout
		if not Game._round_active or Game.play_locked():
			continue
		for n in get_tree().get_nodes_in_group("player"):
			var q := n as Player
			if q and q.is_bot and not q.is_dead:
				p = q
				break
		if p != null:
			break
	_ok(p != null, "a living bot once the round runs")
	if p != null:
		p._spawn_protect = 0.0 # do not gamble on the timer having run out
		p.global_position = Vector3(0, -8, 33)
		p.velocity = Vector3(0, -10, 0) # falling, not just moved: the kill ray wants a drop
	var hud = main.hud
	var found := false
	# Poll instead of one fixed wait: a snapshot, a physics tick and the feed row are three different
	# clocks, and a single 0.5 s window made this check fail at random (it did, four runs in a row).
	for i in 20:
		await get_tree().create_timer(0.1).timeout
		for row in hud.kill_feed.get_children():
			for c in row.get_children():
				if c is TextureRect and (c as TextureRect).texture and (c as TextureRect).texture.resource_path.ends_with("icon_fall.svg"):
					found = true
					break
			if found:
				break
		if found:
			break
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
	get_tree().quit(0 if (found and fails == 0) else 1)
