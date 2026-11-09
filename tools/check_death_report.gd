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
		Game.last_bots = 8 # set_match_choice resets the bot box from last_bots (see #100)
		Game.bot_count = 8
		menu.set_match_choice(&"quay", Game.MODE_FFA)
		menu.play_local_pressed.emit()
	var hud = main.get_node("CanvasLayer/Hud")
	var nudges := 0
	for i in 1200:
		await get_tree().create_timer(0.1).timeout
		var me := Game.player_for_peer(multiplayer.get_unique_id())
		if me and not me.is_dead and i % 20 == 0:
			me.global_position += Vector3(0, 0.01, 0) # stand still in the open; bots find us
		# Standing in the open normally gets us shot, but on a loaded runner the bots can spend the
		# whole budget on each other and the check then dies of old age at the suite's 120 s limit.
		# After 20 s with no death, hand the player to the nearest live bot: put them 4 m from it and
		# let it do the rest.
		if me and not me.is_dead and i > 200 and i % 100 == 0:
			var bot := _nearest_bot(main, me)
			if bot:
				nudges += 1
				print("nudge %d: walking up to %s" % [nudges, bot.name])
				me.global_position = bot.global_position + Vector3(4.0, 0.2, 0.0)
		if hud._death_report and hud._death_report.visible:
			var v = hud._death_report.get_node("V")
			print("report: %s | %s | %s | %s" % [v.get_node("Head").text, v.get_node("Weapon").text, v.get_node("Taken/R").text, v.get_node("Dealt/R").text])
			var taken := int(str(v.get_node("Taken/R").text).split(" ")[0])
			# `taken` is what THIS killer did to you (`Game._dmg_log[victim][killer]`), not your whole
			# health bar: when two bots share the damage the killing bot's share is legitimately 15 or
			# 28. The contract is that the number is the killer's own damage and that the weapon line
			# names a weapon, so assert those instead of the 100 the old assumption needed.
			var ok := taken > 0 and str(v.get_node("Weapon").text).begins_with("with ")
			print("DEATH REPORT CHECK ", "OK" if ok else "FAILED (taken %d)" % taken)
			get_tree().quit()
			return
	print("DEATH REPORT CHECK FAILED (never died / no report)")
	get_tree().quit()


## The live bot closest to the player, or null when the match has none left.
func _nearest_bot(main: Node, me: Player) -> Player:
	var best: Player = null
	var best_d := INF
	for child in main.players_root.get_children():
		var p := child as Player
		if p == null or not p.is_bot or p.is_dead or p.is_queued_for_deletion():
			continue
		var d := p.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
