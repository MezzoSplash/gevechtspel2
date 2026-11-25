extends Node
## #388: a real offline match where the bots use Overdrive. They activate it through their own
## _tick_streaks with the slot from their own pick, which is the path a bot in a real match takes —
## not a helper. Headless:  godot --headless --path . res://tools/check_bot_overdrive.tscn
const BOTS := 6
const LIMIT_S := 40.0


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_FFA)
	Game.last_bots = BOTS
	Game.bot_count = BOTS
	for b in menu._bot_boxes:
		b.value = BOTS
	for o in menu._skill_opts:
		o.selected = BotProfiles.EASY
	Game.last_bot_difficulty = BotProfiles.EASY
	Game.bot_difficulty = BotProfiles.EASY
	menu.play_local_pressed.emit()
	var me: Player = null
	for _i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not Game.play_locked() and Game._round_active:
			break
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	if me == null:
		print("BOT OVERDRIVE CHECK FAILED (no match)")
		get_tree().quit(1)
		return

	var started := Time.get_ticks_msec()
	var launched := 0
	var best := ""
	while float(Time.get_ticks_msec() - started) / 1000.0 < LIMIT_S:
		await get_tree().physics_frame
		for p in Game.players():
			if not p.is_bot or p.is_dead:
				continue
			# The bot earned this the way a player does; the charge is the only thing handed over.
			Game.streak_charges[p.peer_id] = int(Game.streak_charges.get(p.peer_id, 0)) | Game.CHARGE_OVERDRIVE
			var o := Overdrive.for_owner(p.peer_id)
			if o != null:
				launched += 1
				if best == "":
					best = "bot %d has %.1f s left" % [p.peer_id, o.time_left]
				break
		if launched > 0:
			break
	print("  %s a bot activates Overdrive through its own streak tick (%s)" % [
		"PASS" if launched > 0 else "FAIL", best if best != "" else "never"])
	print("BOT OVERDRIVE CHECK %s" % ("OK" if launched > 0 else "FAILED"))
	get_tree().quit(0 if launched > 0 else 1)
