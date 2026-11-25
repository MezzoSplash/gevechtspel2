extends Node
## Client half of the Overdrive network check (#388). Start the server with tools/net_overdrive.sh,
## which runs:  godot --headless -- --server --port 7802 --map quay --mode ffa --bots 2 --test-overdrive
## Everything below is asserted on the CLIENT, because the point is what a joined player gets: the
## faster movement, a server that does not pull him back, the glow the other team must see, and the
## end of the buff. A net check needs its own server, so it is not part of run_checks.
const SERVER_IP := "localhost"
const SERVER_PORT := 7802

var fails := 0


func _ok(made: bool, what: String) -> void:
	print(("  PASS " if made else "  FAIL ") + what)
	if not made:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main) # RPC paths need /root/Main, like the real game
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_host_ip(SERVER_IP)
	menu.set_host_port(SERVER_PORT)
	menu.connect_pressed.emit()
	var me: Player = null
	for _i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not me.is_dead and not Game.play_locked():
			break
	if me == null:
		print("NET OVERDRIVE CHECK FAILED (no pawn)")
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.0).timeout
	# A fresh join can sit behind the class picker, which locks movement.
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false

	# The pick has to contain Overdrive, or the slot for it does not exist: the server only fires the
	# streaks a player picked (#387). The check sends its pick the way the menu does.
	Game.request_streak_choice.rpc_id(1, ["uav", "rcxd", "overdrive"])
	await get_tree().create_timer(0.6).timeout
	var slot := StreakSelect.slot_for(Game, me.peer_id, &"overdrive")
	if slot < 0:
		slot = 2
	# The RPC has to be sent, not called: a plain call runs locally, where the client is not the server.
	Game.request_streak.rpc_id(1, slot)
	var o: Overdrive = null
	for _i in 100:
		o = Overdrive.for_owner(me.peer_id)
		if o != null:
			break
		await get_tree().create_timer(0.1).timeout
	_ok(o != null, "the server's Overdrive reached the client (sync_overdrive)")
	if o == null:
		_finish()
		return
	var started := Time.get_ticks_msec()

	# The buff itself, on the machine that predicts the movement.
	_ok(is_equal_approx(Overdrive.speed_mult(me), 1.25), "25% speed on the client")
	_ok(Overdrive.wallrun_free(me) and Overdrive.dive_free(me), "wallrun and dive are free")
	_ok(o._glow != null and o._glow.is_inside_tree(), "the glow is built, so the other team can see it")
	_ok(o._trail != null, "the trail is there too")
	_ok(o._sfx != null and o._sfx.stream != null, "the cue sound is loaded and heard from far")

	# Not pulled back: sprint for a second and measure how far the *server's* pawn went. A correction
	# would snap it back and the distance would stay under the plain sprint speed.
	var from := me.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var peak := 0.0
	# Two legs, and a turn between them: one straight line runs into a wall and the peak speed is
	# what matters, not the distance. Plain sprint tops out at SPRINT_SPEED; with the buff it does not.
	for leg in 2:
		for _i in 25:
			await get_tree().physics_frame
			peak = maxf(peak, Vector2(me.velocity.x, me.velocity.z).length())
		me._yaw += PI * 0.5
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var moved := from.distance_to(me.global_position)
	_ok(peak > Player.SPRINT_SPEED * 1.1, "the peer saw %.1f m/s on the wire, above the plain %.1f (moved %.1f m)" % [
		peak, Player.SPRINT_SPEED, moved])

	# The end: the server closes it, and the client does not run it forever.
	var gone := false
	while float(Time.get_ticks_msec() - started) / 1000.0 < 14.0:
		await get_tree().create_timer(0.2).timeout
		if Overdrive.for_owner(me.peer_id) == null:
			gone = true
			break
	_ok(gone, "the buff ended by itself (the server's clock, not a local one)")
	_ok(is_equal_approx(Overdrive.speed_mult(me), 1.0), "and the speed is plain again")
	await get_tree().process_frame
	_ok(me.get_node_or_null("OverdriveGlow") == null and me.get_node_or_null("OverdriveTrail") == null,
		"the glow and the trail went with it (review #393)")
	_finish()


func _finish() -> void:
	print("NET OVERDRIVE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
