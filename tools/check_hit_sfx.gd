extends Node
## #207: hit confirm has to carry weight and climb with the combo. Body and headshot must be
## distinguishable blind, the ladder must follow the combo meter, and every layer must stay on the UI
## bus (no clipping into the world mix).
##   godot --headless res://tools/check_hit_sfx.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 2
	Game.bot_count = 2
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null:
			break
	if me == null or me.weapon == null:
		print("  FAIL no local pawn with a weapon")
		print("HIT SFX CHECK: FAIL (1 failures)")
		get_tree().quit(1)
		return
	var w := me.weapon

	_ok(w.thud_sfx != null and w.tick_sfx != null, "the two extra layers exist")
	_ok(w.thud_sfx.bus == &"UI" and w.tick_sfx.bus == &"UI" and w.hit_sfx.bus == &"UI",
		"every hit layer plays on the UI bus")

	# 1) The ladder follows the combo multiplier, and has a ceiling.
	Game._combos[me.peer_id] = {"mult": Combo.MULT_START}
	var flat := w._hit_ladder()
	Game._combos[me.peer_id] = {"mult": Combo.MULT_START + Combo.MULT_STEP * 5.0}
	var high := w._hit_ladder()
	_ok(is_equal_approx(flat, 1.0), "no combo, no pitch offset (%.2f)" % flat)
	_ok(high > flat + 0.2, "a 3.5x combo lifts the hit by %.2f-1.0" % high)
	Game._combos[me.peer_id] = {"mult": Combo.MULT_MAX}
	_ok(w._hit_ladder() <= ComboMeter.PITCH_MAX + 0.001, "the ladder stops at PITCH_MAX")

	# 2) Body and headshot differ: high tick against a low body layer, not just "louder".
	Game._combos[me.peer_id] = {"mult": Combo.MULT_START}
	w._play_hit_fx(false, false)
	var body_pitch := w.hit_sfx.pitch_scale
	var body_thud := w.thud_sfx.pitch_scale
	await get_tree().create_timer(0.25).timeout
	w._play_hit_fx(false, true)
	var head_pitch := w.head_sfx.pitch_scale
	var head_tick := w.tick_sfx.pitch_scale
	_ok(body_thud < 0.75, "a body hit is a low thump (%.2f)" % body_thud)
	_ok(head_pitch > body_pitch + 0.2, "a headshot is clearly higher than a body hit (%.2f vs %.2f)" % [head_pitch, body_pitch])
	_ok(head_tick > head_pitch, "and it has a transient above it (%.2f)" % head_tick)
	_ok(body_pitch >= 0.5 and body_pitch <= 2.0, "body pitch stays in a sane range (%.2f)" % body_pitch)

	# 3) The random offset: ten body hits do not all land on the same pitch.
	var seen := {}
	for i in 10:
		w._play_hit_fx(false, false)
		seen[snappedf(w.hit_sfx.pitch_scale, 0.001)] = true
	_ok(seen.size() > 3, "body hits vary in pitch (%d distinct of 10)" % seen.size())

	# 4) A kill is heavier than a hit: the kill sting plays on top.
	await get_tree().create_timer(0.25).timeout
	w._play_hit_fx(true, false)
	_ok(w.kill_sfx.pitch_scale > 0.5 and w.kill_sfx.playing, "a kill adds the sting")
	Game._combos.erase(me.peer_id)

	print("HIT SFX CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
