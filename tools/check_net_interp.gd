extends Node
## #361/#365: remote poses (humans and bots) carry their sender's clock, land in a buffer and are drawn
## `Game.net_delay_ms` behind the newest one. This drives a synthetic stream through the real buffer on a
## real bot pawn and checks what #365 asks for: no hovering after a jump, no jump bigger than the
## distance travelled, a burst of poses that arrive together does not make the pawn race and freeze, and
## the render time never shifts by more than a frame's worth.
##   godot --headless --path . res://tools/check_net_interp.tscn   → "NET INTERP CHECK OK"
var fails := 0
var _p: Player = null
const FPS := 120.0
const FRAME_MS := 1000.0 / FPS


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


## The sender's timeline: `count` poses at 30 Hz along +X, and optionally one jump from 1.0 s to 1.5 s
## (1 m apex) after which the sender stays on the floor.
func _poses(count: int, speed: float, jump: bool, send0: int) -> Array:
	var out: Array = []
	for i in count:
		var send := send0 + int(i * 1000.0 / 30.0)
		var k := float(i) / 30.0
		var y := 0.0
		if jump and k >= 1.0 and k <= 1.5:
			var u := (k - 1.0) / 0.5
			y = 4.0 * u * (1.0 - u)
		out.append([send, Vector3(speed * k, y, 0.0)])
	return out


## When each pose lands on the client: `latency` +- `jitter`, `burst` poses delivered in one bunch (a
## burst is what makes arrival stamps lie), and every `loss_every`-th pose dropped.
func _delivery(poses: Array, latency: int, jitter: int, burst: int, loss_every: int) -> Array:
	var out: Array = []
	var i := 0
	while i < poses.size():
		var end := mini(i + burst, poses.size())
		var at := 0
		var group: Array = []
		for j in range(i, end):
			if loss_every > 0 and (j + 1) % loss_every == 0:
				continue
			var jit := ((j * 37) % (2 * jitter + 1)) - jitter
			at = maxi(at, int(poses[j][0]) + latency + jit)
			group.append(j)
		for j in group:
			out.append([at, poses[j]])
		i = end
	out.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	return out


## Draw `delivery` at 120 Hz from `t0` to `t1` and report what a player would have seen.
func _sim(delivery: Array, t0: int, t1: int) -> Dictionary:
	_p._pose_buf.clear()
	_p._pose_off_ms = 0
	_p._pose_off_set_ms = 0
	_p._pose_last_arrival_ms = 0
	Game._net_pose_peak_ms = 0.0
	Game._net_delay_f = PawnNet.DELAY_MIN_MS
	Game.net_delay_ms = PawnNet.DELAY_MIN_MS
	Game._net_delay_step_ms = 0
	var i := 0
	var max_step := 0.0
	var freezes := 0
	var max_y := -100.0
	var max_at_change := 0.0
	var at_prev := -1.0
	var back_step := 0.0
	var last := Vector3.ZERO
	var frames := 0
	var samples: Array = [] # [ms, y] of the drawn pawn
	for f in int((t1 - t0) / FRAME_MS):
		var now := int(t0 + f * FRAME_MS)
		while i < delivery.size() and int(delivery[i][0]) <= now:
			var pose: Array = delivery[i][1]
			PawnNet.push_remote_pose(_p, pose[1], int(pose[0]), int(delivery[i][0]))
			i += 1
		PawnNet.tick_remote(_p, FRAME_MS / 1000.0, now)
		var at := float(now - Game.net_delay_ms)
		if at_prev >= 0.0:
			max_at_change = maxf(max_at_change, absf(at - at_prev))
		at_prev = at
		frames += 1
		if frames < 30: # the buffer has to fill first, as after a join
			last = _p.position
			continue
		max_step = maxf(max_step, _p.position.distance_to(last))
		if _p.position.distance_to(last) < 0.001:
			freezes += 1
		back_step = maxf(back_step, last.x - _p.position.x)
		max_y = maxf(max_y, _p.position.y)
		samples.append([now, _p.position.y])
		last = _p.position
	return {
		"max_step": max_step, "freezes": freezes, "max_y": max_y, "max_at_change": max_at_change,
		"back_step": back_step, "delay": Game.net_delay_ms, "samples": samples,
	}


func _ready() -> void:
	await _setup()
	_ok(_p != null, "a bot pawn to draw")
	var t0 := 2000000

	# A clean 30 Hz link: about what the old glide cost, no steps of note, no freezes.
	var clean := _sim(_delivery(_poses(120, 12.0, false, t0), 40, 2, 1, 0), t0, t0 + 3600)
	_ok(float(clean.max_step) < 0.35, "clean: biggest step %.2f m at 12 m/s over 120 Hz frames" % clean.max_step)
	_ok(int(clean.freezes) == 0, "clean: the pawn never stands still (%d frames)" % clean.freezes)
	_ok(int(clean.delay) == PawnNet.DELAY_MIN_MS, "clean: the delay stays at the floor (%d ms)" % clean.delay)
	_ok(float(clean.max_at_change) < 12.0, "clean: the render time moves %.1f ms per frame at most" % clean.max_at_change)

	# 150 ms latency, +-40 ms jitter, 5% loss, four poses landing at once: the burst that broke #361.
	var burst := _sim(_delivery(_poses(150, 12.0, false, t0), 150, 40, 4, 20), t0, t0 + 4000)
	_ok(float(burst.max_step) < 0.9, "burst+loss: biggest step %.2f m" % burst.max_step)
	_ok(int(burst.freezes) <= 2, "burst+loss: at most a frame or two without movement (%d)" % burst.freezes)
	_ok(float(burst.back_step) < 0.35, "burst+loss: no backwards jump (%.2f m)" % burst.back_step)
	_ok(int(burst.delay) > PawnNet.DELAY_MIN_MS + 20, "burst+loss: the delay grew to %d ms" % burst.delay)
	_ok(float(burst.max_at_change) < 12.0, "burst+loss: the render time moves %.1f ms per frame at most" % burst.max_at_change)

	# A jump: the drawn pawn may not hang above the apex or stay in the air after the sender landed.
	var jump := _sim(_delivery(_poses(150, 6.0, true, t0), 150, 40, 4, 20), t0, t0 + 4000)
	_ok(float(jump.max_y) <= 1.12, "jump: never above the 1.00 m apex (%.2f m)" % jump.max_y)
	var too_high := 0
	for s in jump.samples:
		if int(s[0]) >= t0 + 2300 and float(s[1]) > 0.12:
			too_high += 1
	_ok(too_high <= 2, "jump: back on the floor within ~300 ms of landing (%d frames too high)" % too_high)

	# A 400 ms hole in the stream: no throw, and no backwards jump when the next pose lands.
	var holed := _poses(150, 8.0, false, t0)
	var keep: Array = []
	for pose in holed:
		var send := int(pose[0])
		if send < t0 + 900 or send > t0 + 1300:
			keep.append(pose) # the link stalls for the poses sent in that window
	var gap := _sim(_delivery(keep, 60, 10, 2, 0), t0, t0 + 4000)
	_ok(float(gap.max_step) < 1.2, "400 ms hole: biggest step %.2f m" % gap.max_step)
	_ok(float(gap.back_step) < 0.4, "400 ms hole: no backwards jump (%.2f m)" % gap.back_step)

	# A pose that a burst delivered out of order still lands in the right slot.
	_p._pose_buf.clear()
	_p._pose_off_ms = 0
	_p._pose_off_set_ms = 0
	_p._pose_last_arrival_ms = 0
	Game._net_delay_f = PawnNet.DELAY_MIN_MS
	Game.net_delay_ms = PawnNet.DELAY_MIN_MS
	PawnNet.push_remote_pose(_p, Vector3(0, 0, 0), t0, t0 + 200)
	PawnNet.push_remote_pose(_p, Vector3(0.5, 0, 0), t0 + 33, t0 + 205)
	PawnNet.push_remote_pose(_p, Vector3(0.25, 0, 0), t0 + 16, t0 + 210)
	var sorted := true
	for i in range(_p._pose_buf.size() - 1):
		if int(_p._pose_buf[i][0]) > int(_p._pose_buf[i + 1][0]):
			sorted = false
	_ok(sorted and _p._pose_buf.size() == 3, "an out-of-order pose is inserted on its own time (%d samples)" % _p._pose_buf.size())

	# A respawn/LOS snap is far past the travel budget: drawn at once, not slid across the map.
	_p._pose_buf.clear()
	PawnNet.push_remote_pose(_p, Vector3(0, 0, 0), t0, t0)
	PawnNet.tick_remote(_p, 1.0 / 120.0, t0)
	PawnNet.push_remote_pose(_p, Vector3(60, 0, 0), t0 + 33, t0 + 300)
	PawnNet.tick_remote(_p, 1.0 / 120.0, t0 + 300)
	_ok(_p.position.distance_to(Vector3(60, 0, 0)) < 0.01, "a teleport is drawn at once (%.2f m off)" % _p.position.distance_to(Vector3(60, 0, 0)))

	# An older server sends no stamp: the buffer falls back to arrival times and still works.
	_p._pose_buf.clear()
	_p._pose_off_ms = 0
	_p._pose_off_set_ms = 0
	_p._pose_last_arrival_ms = 0
	var moved := 0
	var prev := _p.position
	for i in 40:
		PawnNet.push_remote_pose(_p, Vector3(float(i) * 0.4, 0.0, 0.0), 0, t0 + i * 33)
		PawnNet.tick_remote(_p, 1.0 / 120.0, t0 + i * 33)
		if _p.position.distance_to(prev) > 0.0001:
			moved += 1
		prev = _p.position
	_ok(moved > 10, "no stamp from an old server: still moves (%d frames)" % moved)

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
