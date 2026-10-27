extends Node
## Round-start build-up: plays from the start of the countdown (freeze), fades out 5 s into the round.
##   godot --headless res://tools/check_round_music.tscn
func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.bot_count = 0
	menu.set_match_choice(&"quay", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var in_freeze := false
	var at_go := false
	var gone_by := -1.0
	for i in 400:
		await get_tree().create_timer(0.05).timeout
		var t: AudioStreamPlayer = Game._tension
		var start_on: bool = t.playing and t.stream == Game._tension_start_stream
		if Game.round_frozen and start_on:
			in_freeze = true
		if Game._round_active and not Game.round_frozen:
			var rt: float = Game._round_timer
			if rt < 1.0 and start_on:
				at_go = true
			if rt > 4.5 and rt < 5.0 and not start_on:
				break # stopped too early
			if not start_on and gone_by < 0.0 and rt >= 5.0:
				gone_by = rt
				break
	var ok := in_freeze and at_go and gone_by >= 5.0 and gone_by <= 5.0 + Game.TENSION_FADE + 0.5
	print("music freeze=%s go=%s gone_at=%.2f" % [in_freeze, at_go, gone_by])
	print("ROUND MUSIC CHECK ", "OK" if ok else "FAILED")
	get_tree().quit()
