extends Node
## #381: a shooter's aim reaches another screen. Two halves:
##   1) the pawn really replicates this field: `ads_amt` is in player.tscn's replication config, next to
##      crouch and move_fx (the values the game already syncs from the owner),
##   2) the killcam frame carries whatever the pawn has, so a remote human's ADS lands in the replay.
## The value is set on a pawn of a real match here (a hand-built pawn misses the setup the game does).
##   ./run.sh --headless res://tools/check_ads_sync.tscn   → "ADS SYNC CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	# 1) The replication config: player.tscn lists ads_amt, spawn, always-on (mode 2), like move_fx.
	var cfg := FileAccess.get_file_as_string("res://scenes/player.tscn")
	_ok(cfg.contains("NodePath(\".:ads_amt\")"), "player.tscn replicates ads_amt")
	var lines := cfg.split("\n")
	var idx := -1
	for i in lines.size():
		if lines[i].contains("NodePath(\".:ads_amt\")"):
			idx = i
	if idx >= 0:
		var mode := ""
		for j in range(idx, mini(idx + 4, lines.size())):
			if lines[j].contains("replication_mode"):
				mode = lines[j].strip_edges()
		_ok(mode.ends_with("2"), "and it is always-on (mode 2), so a moving aim is not throttled: %s" % mode)

	# 2) A value on the pawn (what the wire writes) is what the killcam stores, in a real match.
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and not Game.play_locked() and Game._round_active:
			break
	if me == null:
		_ok(false, "a round started")
		print("ADS SYNC CHECK: FAIL (%d failures)" % fails)
		get_tree().quit(1)
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	# A bot with its rope out and its sights up: this is what a client's copy of a remote human holds.
	var other: Player = null
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p != null and p != me and not p.is_dead:
			other = p
			break
	_ok(other != null, "there is another pawn in the match")
	if other == null:
		print("ADS SYNC CHECK: FAIL (%d failures)" % fails)
		get_tree().quit(1)
		return
	other.ads_amt = 1.0
	# The local player's own aim comes from its gun; with no input held it is hip.
	me.ads_amt = 0.0
	var kc: Killcam = Game.killcam
	KillcamRecorder.snapshot(kc)
	_ok(kc._frames.size() >= 1, "the recorder took a snapshot")
	var pawns: Dictionary = kc._frames[kc._frames.size() - 1][1]
	var remote: Array = pawns.get(other.peer_id, [])
	var own: Array = pawns.get(me.peer_id, [])
	_ok(remote.size() >= 11, "the snapshot carries the pawn (#381 field)")
	if remote.size() >= 11:
		_ok(is_equal_approx(float(remote[10]), 1.0), "a remote human's ADS lands in the frame (%.2f)" % float(remote[10]))
	if own.size() >= 11:
		_ok(is_equal_approx(float(own[10]), 0.0), "someone not aiming is hip in the frame")
	_ok(remote.size() >= 13, "and so do grappling and its anchor")
	print("ADS SYNC CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
