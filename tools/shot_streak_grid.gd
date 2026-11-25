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

		# Empty: no slots filled. Only the screenshot forces that state; the game always keeps at least
		# one pick (sanitize falls back to the default), so this shows the empty frames of the layout.
		ed._pick = []
		ed.focus_index(0)
		ed._refresh_slots()
		await _grab("%s/grid_empty_%s.png" % [OUT, tag])

		# Three chosen, focus on a picked tile.
		StreakSelect.set_local(Game, ["uav", "rcxd", "los"])
		ed.refresh()
		ed.focus_index(2)
		await _grab("%s/grid_three_%s.png" % [OUT, tag])

		# The collision: LOS is picked, the focus sits on Overdrive, which is dimmed with the reason.
		# Two picks, not three: with a full row the "3 at most" rule would report first and hide the
		# 7-kill clash this screenshot is about.
		StreakSelect.set_local(Game, ["uav", "los"])
		ed.refresh()
		ed.focus_index(3)
		await _grab("%s/grid_conflict_%s.png" % [OUT, tag])

	get_tree().quit()


func _grab(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
