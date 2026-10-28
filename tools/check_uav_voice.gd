extends Node
## UAV voice cooldown: the "radar online" lines play at most once per RADAR_VOICE_COOLDOWN per type,
## the popup text still comes every time.
##   godot --headless res://tools/check_uav_voice.tscn   → "UAV VOICE CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var hud = main.get_node("CanvasLayer/Hud")
	var log: Array = hud.radar_voice_log
	for i in 5:
		hud.show_radar_event("Bot %d" % i, 1, false)
	hud.show_radar_event("Mate", 0, true)
	hud.show_radar_event("Mate2", 0, true)
	_ok(log.count("enemy") == 1, "5 enemy UAVs in a row: one voice line (%d)" % log.count("enemy"))
	_ok(log.count("friendly") == 1, "friendly has its own cooldown: one line (%d)" % log.count("friendly"))
	_ok(hud.RADAR_VOICE_COOLDOWN >= 15.0 and hud.RADAR_VOICE_COOLDOWN <= 30.0, "cooldown %.0f s" % hud.RADAR_VOICE_COOLDOWN)
	# after the cooldown it plays again
	for k in hud._radar_voice_t.keys():
		hud._radar_voice_t[k] = float(hud._radar_voice_t[k]) - hud.RADAR_VOICE_COOLDOWN - 0.1
	hud.show_radar_event("Bot 9", 1, false)
	_ok(log.count("enemy") == 2, "after the cooldown: plays again")
	# RC-XD lines (same cooldown, own types)
	for i in 4:
		hud.show_rc_event("Bot %d" % i, 1, false)
	hud.show_rc_event("Me", 0, true)
	hud.show_rc_event("Me", 0, true)
	_ok(log.count("rcxd_enemy") == 1, "4 enemy RC-XDs: one 'Enemy RC-XD inbound' (%d)" % log.count("rcxd_enemy"))
	_ok(log.count("rcxd_friendly") == 1, "friendly RC-XD: one 'Friendly RC-XD deployed' (%d)" % log.count("rcxd_friendly"))
	_ok(hud._announcer.stream != null and hud._announcer.stream.resource_path.ends_with("rcxd_friendly.wav"), "plays rcxd_friendly.wav")
	_ok(load("res://assets/sounds/rcxd_enemy.wav") != null, "rcxd_enemy.wav loads")
	print("UAV VOICE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)
