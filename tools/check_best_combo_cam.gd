extends Node
## Best-trickshot killcam end to end: several landed combos far apart in time (older than the 7 s
## replay buffer), across two players; the round-end replay must be the single biggest one.
##   godot --headless res://tools/check_best_combo_cam.tscn   → "BEST COMBO CAM CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _alive(id: int) -> Player:
	for i in 100:
		var p := Game.player_for_peer(id)
		if p and not p.is_dead:
			return p
		await get_tree().create_timer(0.1).timeout
	return null


## killer lands a combo of `moves` on victim with a real death (so the killcam records it).
func _land(killer: int, victim: int, moves: Array) -> Dictionary:
	var v: Player = await _alive(victim)
	var k: Player = await _alive(killer)
	if v == null or k == null:
		return {}
	v._spawn_protect = 0.0
	Game._combos.erase(killer)
	for m in moves:
		Game.combo_move(killer, m)
	var c := Game.combo_of(killer)
	var expect := roundi(float(c.pts) * float(c.mult))
	v.apply_hit(v.global_position + Vector3(0, 1, 0), Vector3.UP, 999.0, false, killer, &"rifle", 1.0, k.global_position)
	return {"pts": expect, "t": Game.killcam._clock, "id": Game._trick_seq, "k": killer, "v": victim}


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_STYLE_FFA)
	for b in menu._bot_boxes:
		b.value = 2
	for b in menu._kill_boxes:
		b.value = 50
	for b in menu._time_boxes:
		b.value = 10
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and not Game.play_locked() and Game.player_for_peer(1):
			break
	var bots: Array[int] = []
	for id in Game.scores:
		if int(id) < 0:
			bots.append(int(id))
	_ok(bots.size() == 2, "two bots")
	var big := [Combo.WALLRUN, Combo.WALLJUMP, Combo.WALL_TO_WALL, Combo.DIVE, Combo.ROLL, Combo.SLIDE, Combo.SURF]
	var landed: Array = []
	landed.append(await _land(1, bots[0], [Combo.SLIDE, Combo.AIR])) # small, by me
	await get_tree().create_timer(1.5).timeout
	landed.append(await _land(bots[1], bots[0], big)) # the biggest, by a bot, early
	await get_tree().create_timer(Killcam.KEEP + 2.0).timeout # past KEEP: only a stored clip can replay it now
	landed.append(await _land(1, bots[1], [Combo.WALLRUN, Combo.WALLJUMP, Combo.DIVE])) # medium, recent
	# Metric: a trick kill without a combo is best only until someone lands a combo; after that a
	# smaller combo still beats it (the spot is for the biggest single combo).
	var saved := Game.best_trick.duplicate()
	var fake := {"k": 1, "v": 4242, "kn": "me", "vn": "x", "kt": 0, "vt": 0, "w": "knife", "hs": false, "tags": ""}
	var no_combo: Array[StringName] = [Style.YEET_X2, Style.SPIN, Style.WALLJUMP, Style.HS_STREAK]
	Game.best_trick.clear()
	Game._combos.erase(1)
	Game._style_chain.erase(1)
	Game._award_style(fake, no_combo)
	var trick_pts := int(Game.best_trick.get("pts", 0))
	_ok(trick_pts >= 1000 and int(Game.best_trick.get("bank", -1)) == 0, "no combo yet: the %d trick kill is best" % trick_pts)
	Game.combo_move(1, Combo.WALLRUN)
	Game.combo_move(1, Combo.WALLJUMP)
	var empty: Array[StringName] = []
	Game._award_style(fake, empty)
	_ok(int(Game.best_trick.get("bank", 0)) == 210, "a 210 combo beats the %d trick kill" % trick_pts)
	Game._combos.erase(1)
	Game._award_style(fake, no_combo)
	_ok(int(Game.best_trick.get("bank", 0)) == 210, "a later bigger trick kill without combo does not take it back")
	Game.best_trick = saved
	await get_tree().create_timer(2.0).timeout
	for l in landed:
		print("  landed ", l)
	var best: Dictionary = landed[1]
	_ok(int(Game.best_trick.get("pts", 0)) == int(best.pts), "best_trick is the biggest combo (%s vs %d)" % [Game.best_trick.get("pts", -1), best.pts])
	_ok(int(Game.best_trick.get("trick_id", -1)) == int(best.id), "best_trick id %s == %d" % [Game.best_trick.get("trick_id", -1), best.id])
	_ok(int(Game.killcam._trick_clip.get("trick_id", -1)) == int(best.id), "stored replay is the biggest (%s)" % Game.killcam._trick_clip.get("trick_id", -1))
	Game._end_round_player(1)
	var kc = Game.killcam
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		if kc._playing:
			break
	_ok(kc._playing, "final killcam plays")
	_ok(is_equal_approx(Killcam.PRE, 5.0) and is_equal_approx(Killcam.POST, 2.0) and Killcam.KEEP >= Killcam.PRE + Killcam.POST + 0.4 + Killcam.POST,
		"timings: %.1f s before, %.1f s after, buffer %.1f s" % [Killcam.PRE, Killcam.POST, Killcam.KEEP])
	var fr: Array = kc._clip.frames
	_ok(float(kc._clip.t_kill) - float(fr[0][0]) >= Killcam.PRE and float(fr[-1][0]) - float(kc._clip.t_kill) >= Killcam.POST,
		"stored clip covers PRE before and POST after the kill")
	_ok(int(Game.killcam_pick().get("bank", 0)) == int(landed[1].pts), "pick carries the combo payout")
	var info: Dictionary = kc._clip.get("info", {})
	_ok(int(info.get("trick_id", -1)) == int(best.id), "replays the biggest combo (trick %s, want %d)" % [info.get("trick_id", -1), best.id])
	_ok(is_equal_approx(float(kc._clip.get("t_kill", -1.0)), float(best.t)), "the replay is that kill's moment (%.2f vs %.2f)" % [kc._clip.get("t_kill", -1.0), best.t])
	print("BEST COMBO CAM CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)
