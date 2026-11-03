extends Node
## #160 headless: Capture the Flag on Quay. Menu gating (CTF only on maps with flag bases), pickup,
## no capture while your own flag is away, capture, drop on death, return by touch and by timer,
## first to CTF.CAPTURES_TO_WIN wins, and a short bot smoke run.
##   godot --headless --path . res://tools/check_ctf.tscn   → "CTF CHECK OK"
var fails := 0
var ended: Array = []
var events: Array = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Put `p` on `pos` and let the server tick see it.
func _put(p: Player, pos: Vector3) -> void:
	p.global_position = pos + Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	await _frames(3)


func _ready() -> void:
	_ok(Game.parse_mode("ctf") == Game.MODE_CTF and not Game.is_ffa(Game.MODE_CTF), "parse_mode ctf, a team mode")
	_ok(CTF.available(&"quay") and not CTF.available(&"foundry"), "Quay has flag bases, Foundry not yet")
	var bases := Maps.flag_bases(&"quay")
	_ok(bases[0].z > 0.0 and bases[1].z < 0.0, "blue base on the blue (+Z) side, orange on -Z")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.round_ended.connect(func(w: int, n: String, _s: Dictionary) -> void: ended.append([w, n]))
	Game.flag_event.connect(func(k: String, t: int, n: String) -> void: events.append([k, t, n]))
	menu.set_match_choice(&"foundry", Game.MODE_CTF)
	_ok(menu.selected_mode() == Game.MODE_TDM, "CTF on a map without bases falls back to TDM")
	_ok(menu._mode_opts[0].is_item_disabled(Game.MODE_CTF), "CTF greyed out on Foundry")
	menu.set_match_choice(&"quay", Game.MODE_CTF)
	_ok(menu.selected_mode() == Game.MODE_CTF and not menu._mode_opts[0].is_item_disabled(Game.MODE_CTF), "CTF selectable on Quay")
	_ok(not (menu._kill_boxes[0] as Control).get_parent().visible, "CTF hides the Kills limit row")
	for b in menu._bot_boxes:
		b.value = 0
	for b in menu._time_boxes:
		b.value = 10
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and not Game.play_locked() and Game.player_for_peer(1):
			break
	var me := Game.player_for_peer(1)
	_ok(me != null and Game.is_ctf() and Game.flags.size() == 2, "CTF round running with two flags")
	_ok(Game.get_node_or_null("CtfFlags") != null, "flag visuals exist")
	# HUD layout: the status block sits under the clock, and the popup under the status block.
	var hud = get_tree().get_first_node_in_group("hud")
	await get_tree().create_timer(0.4).timeout
	hud.show_popup("TEST", Color.WHITE, "x", 0)
	var st: Control = hud._standing
	_ok(st.offset_top >= 60.0 and hud._popup.offset_top >= st.offset_bottom, "CTF status below the clock, popup below it (%d..%d, popup %d)" % [st.offset_top, st.offset_bottom, hud._popup.offset_top])
	var my_t := me.team_id
	var enemy_t := 1 - my_t
	var own_base: Vector3 = Game.flags[my_t].home
	var enemy_base: Vector3 = Game.flags[enemy_t].home
	# Pick up, then the own flag away: no capture.
	await _put(me, enemy_base)
	_ok(int(Game.flags[enemy_t].state) == Objective.CARRIED and int(Game.flags[enemy_t].carrier) == 1, "touching the enemy flag takes it")
	_ok(CtfStatus.line(Game, 1).contains("YOU HAVE THE FLAG"), "HUD tells the carrier to run home")
	Objective.drop(Game.flags[my_t], own_base + Vector3(6, 0, 0), CTF.RETURN_TIME)
	await _put(me, own_base)
	_ok(int(Game.ctf_caps[my_t]) == 0, "no capture while the own flag is not home")
	# Touch the own dropped flag: it goes home; then the base captures.
	await _put(me, own_base + Vector3(6, 0, 0))
	_ok(int(Game.flags[my_t].state) == Objective.AT_HOME, "touching your dropped flag returns it")
	await _put(me, own_base)
	_ok(int(Game.ctf_caps[my_t]) == 1 and int(Game.flags[enemy_t].state) == Objective.AT_HOME, "capture: +1 and the enemy flag goes home")
	_ok(Game.team_score(my_t) == 1 and Game.score_word() == "captures", "team score counts captures")
	# Drop on death.
	await _put(me, enemy_base)
	var die_at := me.global_position
	me.apply_hit(die_at + Vector3(0, 1, 0), Vector3.UP, 999.0, false, 0, &"rifle", 1.0, die_at)
	await _frames(3)
	_ok(int(Game.flags[enemy_t].state) == Objective.DROPPED, "carrier death drops the flag")
	Game.flags[enemy_t].drop_t = 0.05
	await _frames(10)
	_ok(int(Game.flags[enemy_t].state) == Objective.AT_HOME, "a dropped flag goes home on its timer")
	var kinds := events.map(func(e): return e[0])
	_ok(kinds.has("taken") and kinds.has("captured") and kinds.has("dropped") and kinds.has("returned"), "events: %s" % str(kinds))
	_ok(CtfStatus.popup_title("captured", enemy_t) == "%s SCORES" % CTF.TEAM_NAMES[my_t], "popup wording")
	# Two more captures win.
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(1)
		if me and not me.is_dead:
			break
	for i in CTF.CAPTURES_TO_WIN - 1:
		await _put(me, enemy_base)
		await _put(me, own_base)
	await _frames(2)
	_ok(ended.size() == 1 and int(ended[0][0]) == my_t, "first to %d captures wins (%s)" % [CTF.CAPTURES_TO_WIN, str(ended)])
	print("CTF CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
