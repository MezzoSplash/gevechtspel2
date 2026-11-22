extends Node
## #361: remote poses (humans and bots) are buffered and drawn `Game.net_delay_ms` behind the newest,
## so a lost or late pose no longer shows a frozen pawn and then a jump. This drives a synthetic 30 Hz
## pose stream through the real buffer on a real bot pawn: 12 m/s along +X, 40 ms one-way latency,
## jitter, and 5% loss.
##   godot --headless --path . res://tools/check_net_interp.tscn   → "NET INTERP CHECK OK"
var fails := 0
var _p: Player = null


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _setup() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_STYLE_FFA)
	for b in menu._bot_boxes:
		b.value = 2
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and Game.player_for_peer(1):
			break
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and p.is_bot:
			p._bot_brain = null # the buffer is the only thing moving this pawn now
			p.set_physics_process(false)
			_p = p
			break


## One synthetic run: returns {max_step, freezes, travelled, delay_ms}.
func _run(speed: float, loss_every: int, frames: int, jitter_ms := 2) -> Dictionary:
	_p._pose_buf.clear()
	Game._net_pose_peak_ms = 0.0
	Game.net_delay_ms = PawnNet.DELAY_MIN_MS
	var t0 := 1000000
	var step_ms := 1000.0 / 30.0
	var frame_ms := 1000.0 / 120.0
	var sent := 0
	var next_at := t0 # arrival time of the next pose
	var last := Vector3.ZERO
	var max_step := 0.0
	var freezes := 0
	var travelled := 0.0
	for f in frames:
		var frame_t := int(t0 + f * frame_ms)
		while next_at <= frame_t:
			var send := next_at - 40 # 40 ms one-way
			var dist := speed * float(send - t0) / 1000.0
			sent += 1
			if loss_every > 0 and sent % loss_every == 0:
				next_at += step_ms # dropped: nothing arrives
				continue
			var jitter := float((sent * 37) % (2 * jitter_ms + 1)) - float(jitter_ms)
			PawnNet.push_remote_pose(_p, Vector3(dist, 0.0, 0.0), int(next_at + jitter))
			next_at += step_ms
		PawnNet.tick_remote(_p, frame_ms / 1000.0, frame_t)
		var d: float = Vector2(_p.position.x - last.x, _p.position.z - last.z).length()
		if f > 12: # skip the first pose
			max_step = maxf(max_step, d)
			travelled += d
			if d < 0.001:
				freezes += 1
			last = _p.position
		elif f == 12:
			last = _p.position
	return {"max_step": max_step, "freezes": freezes, "travelled": travelled, "delay": Game.net_delay_ms}


func _ready() -> void:
	await _setup()
	_ok(_p != null, "a bot pawn to draw")

	# A clean 30 Hz link: the old glide cost, no big steps, no freezes.
	var clean := _run(12.0, 0, 360)
	_ok(float(clean.max_step) < 0.35, "clean: biggest step %.2f m at 12 m/s over 120 Hz frames" % clean.max_step)
	_ok(int(clean.freezes) == 0, "clean: the pawn never stands still (%d frames)" % clean.freezes)
	_ok(float(clean.travelled) > 12.0 * 3.0 * 0.8, "clean: it covers the distance (%.1f m in ~3 s)" % clean.travelled)
	_ok(int(clean.delay) == PawnNet.DELAY_MIN_MS, "clean: the delay stays at the floor (%d ms)" % clean.delay)

	# 5% loss and jitter: still no jumps, and the delay adapts upward while it lasts.
	var lossy := _run(12.0, 20, 360, 10)
	_ok(float(lossy.max_step) < 0.9, "5%% loss: biggest step %.2f m (was a jump of metres before #361)" % lossy.max_step)
	_ok(int(lossy.freezes) <= 2, "5%% loss: at most a frame or two without movement (%d)" % lossy.freezes)
	_ok(float(lossy.travelled) > 12.0 * 3.0 * 0.75, "5%% loss: it still covers the distance (%.1f m)" % lossy.travelled)
	_ok(int(lossy.delay) > PawnNet.DELAY_MIN_MS, "5%% loss: the interpolation delay grew to %d ms" % lossy.delay)

	# A respawn/LOS snap is far past the travel budget: drawn at once, not slid across the map.
	_p._pose_buf.clear()
	PawnNet.push_remote_pose(_p, Vector3(0, 0, 0), 2000000)
	PawnNet.tick_remote(_p, 1.0 / 120.0, 2000000)
	PawnNet.push_remote_pose(_p, Vector3(60, 0, 0), 2000033)
	PawnNet.tick_remote(_p, 1.0 / 120.0, 2000333)
	_ok(_p.position.distance_to(Vector3(60, 0, 0)) < 0.01, "a teleport is drawn at once (%.2f m off)" % _p.position.distance_to(Vector3(60, 0, 0)))

	# Lag compensation must know about the interpolation delay, or shots land behind the target.
	_ok(LagComp.INTERP_MS >= PawnNet.DELAY_MAX_MS, "LagComp allows the full interpolation delay (%d ms)" % LagComp.INTERP_MS)
	Game._server_clock_offset = 5000
	Game.net_delay_ms = PawnNet.DELAY_MAX_MS
	var early := LagComp.view_ms(Game)
	Game.net_delay_ms = PawnNet.DELAY_MIN_MS
	_ok(early + (PawnNet.DELAY_MAX_MS - PawnNet.DELAY_MIN_MS) == LagComp.view_ms(Game), "view_ms is stamped with the world we draw")
	Game._server_clock_offset = 0

	print("NET INTERP CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
