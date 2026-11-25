extends Node
## #387 tile grid screenshots to /home/gianni/OpenBot/Shared/gevechtspel2-streak-grid/ (needs a display,
## e.g. xvfb-run): empty slots, three chosen, and the 7-kill collision while LOS is picked — at
## 1920x1080 and 1280x720.
const OUT := "/home/gianni/OpenBot/Shared/gevechtspel2-streak-grid"
const SIZES := [Vector2i(1920, 1080), Vector2i(1280, 720)]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.show_screen("streaks")
	var ed: StreakEditor = menu.streak_editor
	await get_tree().create_timer(0.4).timeout

	for size in SIZES:
		get_window().size = size
		var tag := "%dx%d" % [size.x, size.y]
		await get_tree().create_timer(0.25).timeout

		# Three chosen, the focus on a chosen tile: white frame plus the accent slot number.
		StreakSelect.set_local(Game, ["uav", "rcxd", "los"])
		ed.refresh()
		ed.focus_index(2)
		await get_tree().process_frame
		await _grab("%s/grid_focus_chosen_%s.png" % [OUT, tag])

		# The focus on a free tile: only the white frame, no slot number.
		StreakSelect.set_local(Game, ["uav", "rcxd"])
		ed.refresh()
		ed.focus_index(2)
		await get_tree().process_frame
		await _grab("%s/grid_focus_free_%s.png" % [OUT, tag])

		# The collision: LOS is picked, Overdrive is dimmed with the reason in the info panel.
		StreakSelect.set_local(Game, ["uav", "los"])
		ed.refresh()
		ed.focus_index(3)
		await get_tree().process_frame
		await _grab("%s/grid_conflict_%s.png" % [OUT, tag])

	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
