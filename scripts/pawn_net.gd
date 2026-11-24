class_name PawnNet
extends RefCounted
## How a pawn lives on other machines (#316): a bot's pose from sync_bot_poses, the nametag and its line
## of sight, the synced position with the server's claim check (#B1) and its corrections, the LOS snap,
## a remote human's glide and a remote pawn's visuals. Static on the pawn `p`, like Movement; Player keeps
## the synced properties, the state and its old function names, so nothing on the wire changes.


## Client-side bot transform from Game.sync_bot_poses (Synchronizer is off for bots).
## `stance` (optional, newer servers): [crouch, move_fx], so remote bots crouch, dive and wall-run visibly.
## `sent_ms` (#365): the server clock when the pose was made; 0 from an older server.
static func apply_network_pose(p: Player, pos: Vector3, yaw: float, pitch: float, stance: Array = [], sent_ms: int = 0) -> void:
	push_remote_pose(p, pos, sent_ms) # the drawn position comes from the buffer, the rest is immediate
	p.rotation.y = yaw
	p._yaw = yaw
	p._pitch = pitch
	if p.head:
		p.head.rotation.x = pitch
	p.velocity = Vector3.ZERO
	if stance.size() >= 2:
		p.crouch = clampf(float(stance[0]), 0.0, 1.0)
		# #371: the slide is a stance of its own and was invisible to everyone else (the sync carried only
		# crouch and move_fx), so a sliding bot and a crawling bot looked the same on another screen.
		if stance.size() >= 3:
			p._sliding = float(stance[2]) > 0.5
		var was := p.move_fx
		p.move_fx = int(stance[1])
		p._apply_stance()
		# A remote pawn never runs Movement.tick_dive_roll, so _roll_t stays 0 and the roll was
		# invisible on everyone else's screen and in the killcam (#236). The synced move_fx is the
		# signal: the frame it turns MOVE_ROLL, run the local timer that drives the body's flip.
		if p.move_fx == p.MOVE_ROLL and was != p.MOVE_ROLL:
			p._roll_t = p.ROLL_TIME
	if p.body_mesh:
		p.body_mesh.visible = not p.is_dead
	if p.nametag:
		p.nametag.text = p.display_name


## Teammates keep their tag through walls (where is my team). Enemies only show it in line of sight,
## so the tag is no wallhack and the UAV streak (minimap) is still the way to find them.
static func update_nametag(p: Player, delta: float, force: bool = false) -> void:
	if p.nametag == null or p.is_local():
		return
	if Game.is_dedicated or DisplayServer.get_name() == "headless":
		p.nametag.visible = false
		return
	p._tag_check_t -= delta
	if force or p._tag_check_t <= 0.0:
		p._tag_check_t = p.TAG_CHECK + randf() * 0.03 # spread the rays over frames
		var me := Game.player_for_peer(p.multiplayer.get_unique_id())
		var mate := me != null and not Game.is_enemy(p, me)
		p.nametag.no_depth_test = mate
		p._tag_show = mate or p._enemy_in_sight()
	p.nametag.visible = p._tag_show and not p.is_dead


## World-only rays (players do not block) from the active camera to the head and the chest.
static func enemy_in_sight(p: Player) -> bool:
	var cam := p.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var space := p.get_world_3d().direct_space_state
	var from := cam.global_position
	for to in [p.head_point(), p.aim_point()]:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		if space.intersect_ray(query).is_empty():
			return true
	return false


## --- #361/#365: remote pose interpolation on the sender's clock ---
## Every pose carries the time its sender stamped it with (`sent`), so order and spacing come from the
## sender, not from the network. Before this the client stamped poses on arrival, and a burst of four
## poses covering 130 ms got four arrival stamps a few ms apart: the pawn raced through them, stopped,
## and then extrapolated (also upwards, hence the hovering). The client maps the sender's clock onto
## its own with the average (arrival - sent) of the last ~2 s of poses, and draws
## `Game.net_delay_ms` behind the newest pose. That delay rises at most DELAY_UP_MS_S and falls at most
## DELAY_DOWN_MS_S, so the render time never jumps in a frame.
const DELAY_MIN_MS := 55
const DELAY_MAX_MS := 150
const DELAY_UP_MS_S := 600.0 # per second: covers a burst within ~0.2 s, ~5 ms per frame
const DELAY_DOWN_MS_S := 10.0
## A stall longer than this carries the last horizontal motion, never vertically (#365).
const EXTRAP_MAX_MS := 80
const BUFFER_MAX := 90
const OFFSET_AVG_POSES := 60.0 # the clock offset averages about 2 s of poses at 30 Hz
const STALE_KEEP_MS := 300 # a pose this far behind the newest is a late duplicate: dropped
const GAP_DECAY := 0.98 # per 1/30 s: the delay target falls back within a second or two of a clean link


## A pose arrived for `p` (client side). `sent_ms` is the sender's own stamp (0: none, older peer or an
## old server, then the arrival time is used). `at_ms` is when it arrived; negative means now, checks
## pass their own timeline. A jump the server would refuse as a claim is a teleport (respawn, LOS snap,
## a correction) and is drawn at once instead of sliding the pawn over the map.
static func push_remote_pose(p: Player, pos: Vector3, sent_ms: int = 0, at_ms: int = -1) -> void:
	var arrival := Time.get_ticks_msec() if at_ms < 0 else at_ms
	var t := arrival
	if sent_ms > 0:
		p._pose_stamped = true
		_note_offset(p, arrival - sent_ms)
		t = sent_ms + p._pose_off_ms
		_note_late(p, arrival - t, sent_ms)
		Game._net_pose_stamped = true
	elif p._pose_stamped and not p._pose_buf.is_empty():
		# An unstamped copy next to a stamped stream (sync_pawns' roster snapshot on a join): the stream
		# has the real timeline, and an arrival stamp here would only put a pose out of place.
		return
	else:
		_note_gap(p, arrival) # no stamp (an old server): only the arrival gaps tell how much buffer
	if p._pose_buf.is_empty():
		# The first pose (a join, or after a cut) is drawn where it is, not slid over from wherever the
		# node stood: the frame limiter would drag it across the map at walking speed.
		p.position = pos
	else:
		var newest: Array = p._pose_buf[-1]
		if t < int(newest[0]) - STALE_KEEP_MS:
			return # far too late: drawing it would drag the pawn backwards
		var dt := maxf(float(t - int(newest[0])) / 1000.0, p.NET_CLAIM_MIN_DT)
		if not claim_reachable_delta(p, pos - (newest[1] as Vector3), dt):
			p._pose_buf.clear()
			p.position = pos
	_insert_pose(p, t, pos)


## Forget everything measured about this pawn's stream (checks, a reused pawn).
static func reset_stream(p: Player) -> void:
	p._pose_buf.clear()
	p._pose_off_ms = 0
	p._pose_off_has = false
	p._pose_off_f = 0.0
	p._pose_off_n = 0
	p._pose_prev_sent = 0
	p._pose_stamped = false
	p._pose_last_arrival_ms = 0


## Sorted on the sender's time, so a pose that a burst delivered out of order still lands in the right
## slot instead of being glued to the end of the buffer.
static func _insert_pose(p: Player, t: int, pos: Vector3) -> void:
	var i := p._pose_buf.size()
	while i > 0 and int(p._pose_buf[i - 1][0]) > t:
		i -= 1
	p._pose_buf.insert(i, [t, pos])
	while p._pose_buf.size() > BUFFER_MAX:
		p._pose_buf.pop_front()


## The sender's clock onto ours. Only the spacing of the stamps matters for the path; the offset is a
## shift, and it has to be a steady one. It is the average (arrival - sent) of about OFFSET_AVG_POSES
## poses: a plain mean over the first ones, then a slow moving average, so jitter, a burst or a route
## change moves it a millisecond at a time instead of in a step. The fastest pose ever seen (the first
## try) put most poses 200+ ms "late" on a jittery link, more than the buffer can hold: the pawn froze.
static func _note_offset(p: Player, diff_ms: int) -> void:
	p._pose_off_last = diff_ms
	p._pose_off_n += 1
	if not p._pose_off_has:
		p._pose_off_has = true
		p._pose_off_f = float(diff_ms)
	else:
		var alpha := maxf(1.0 / float(p._pose_off_n), 1.0 / OFFSET_AVG_POSES)
		p._pose_off_f += (float(diff_ms) - p._pose_off_f) * alpha
	p._pose_off_ms = int(roundf(p._pose_off_f))


## How much buffer a stamped stream needs: a pose drawn at `at` must have landed by `at + delay`, and
## so must the one after it. So the delay covers how late a pose is against its own stamp (`late_ms`,
## jitter and bursts alike) plus the stamp gap to the pose before it (one interval, two after a loss).
static func _note_late(p: Player, late_ms: int, sent_ms: int) -> void:
	var span := 1000 / 30
	if p._pose_prev_sent > 0:
		span = clampi(sent_ms - p._pose_prev_sent, 0, 200)
	p._pose_prev_sent = maxi(p._pose_prev_sent, sent_ms)
	Game._net_pose_peak_ms = maxf(Game._net_pose_peak_ms, float(late_ms + span))


## Without stamps the buffer is sized by how bunched the arrivals are (the #361 measure).
static func _note_gap(p: Player, arrival: int) -> void:
	if p._pose_last_arrival_ms > 0 and arrival > p._pose_last_arrival_ms:
		Game._net_pose_peak_ms = maxf(Game._net_pose_peak_ms, float(arrival - p._pose_last_arrival_ms))
	if arrival > p._pose_last_arrival_ms:
		p._pose_last_arrival_ms = arrival


## The machine-wide delay, stepped once per frame (many pawns tick): up quickly, down slowly (#365).
## `now` is the clock being rendered at, so a check can drive it with its own timeline.
static func _step_delay(now: int, delta: float) -> void:
	if now == Game._net_delay_step_ms:
		return
	Game._net_delay_step_ms = now
	# The peak fades with time, not per pose: with ten bots it was forgotten ten times as fast.
	Game._net_pose_peak_ms *= pow(GAP_DECAY, 30.0 * maxf(delta, 0.0))
	# A stamped peak is already the buffer needed; an arrival gap (no stamps) keeps its 1.5x margin.
	var target := clampf(Game._net_pose_peak_ms if Game._net_pose_stamped else 1.5 * Game._net_pose_peak_ms, float(DELAY_MIN_MS), float(DELAY_MAX_MS))
	var f := Game._net_delay_f
	f = move_toward(f, target, (DELAY_UP_MS_S if target > f else DELAY_DOWN_MS_S) * maxf(delta, 0.001))
	Game._net_delay_f = f
	Game.net_delay_ms = int(f)


## Client: draw remote pawn `p` at the pose `Game.net_delay_ms` behind the newest one.
## `at_ms` is the clock to render at; negative means now (checks pass their own timeline).
static func tick_remote(p: Player, delta: float, at_ms: int = -1) -> void:
	if p._pose_buf.is_empty():
		return
	var now := Time.get_ticks_msec() if at_ms < 0 else at_ms
	_step_delay(now, delta)
	var at := float(now - Game.net_delay_ms)
	var newest: Array = p._pose_buf[-1]
	if at > float(newest[0]):
		# Nothing newer has arrived: carry the last horizontal motion briefly. Never vertically, so a
		# jump ends on the last known height instead of hanging above its apex (#365).
		var ext := minf(at - float(newest[0]), EXTRAP_MAX_MS) / 1000.0
		var vel := _pose_velocity(p)
		var d: Vector3 = newest[1]
		_draw(p, Vector3(d.x + vel.x * ext, d.y, d.z + vel.z * ext), delta)
		return
	var a: Array = p._pose_buf[0]
	var b: Array = p._pose_buf[0]
	for i in range(p._pose_buf.size() - 1, -1, -1):
		if float(p._pose_buf[i][0]) <= at:
			a = p._pose_buf[i]
			b = p._pose_buf[mini(i + 1, p._pose_buf.size() - 1)]
			break
	var out: Vector3 = a[1]
	if float(b[0]) > float(a[0]) and float(b[0]) > at:
		out = (a[1] as Vector3).lerp(b[1] as Vector3, (at - float(a[0])) / float(int(b[0]) - int(a[0])))
	_draw(p, out, delta)
	# Drop what the render time has left behind, keeping a couple of samples for the lerp.
	while p._pose_buf.size() > 3 and float(p._pose_buf[1][0]) <= at:
		p._pose_buf.pop_front()


## Put the drawn pawn down, limiting how far it may move in one frame to the stream's own speed plus a
## margin: a sample that a burst left slightly out of order cannot zig-zag the path, and on a clean link
## nothing is limited.
static func _draw(p: Player, out: Vector3, delta: float) -> void:
	var from := p.position
	var lim := (_pose_speed(p) + 3.0) * maxf(delta, 0.001)
	if out.distance_to(from) > lim and lim > 0.0:
		out = from + (out - from).normalized() * lim
	p.position = out


## Metres per second over the last two poses, capped at what the server accepts as movement.
static func _pose_velocity(p: Player) -> Vector3:
	if p._pose_buf.size() < 2:
		return Vector3.ZERO
	var a: Array = p._pose_buf[-2]
	var b: Array = p._pose_buf[-1]
	var dt := maxf(float(int(b[0]) - int(a[0])) / 1000.0, 0.001)
	var v: Vector3 = ((b[1] as Vector3) - (a[1] as Vector3)) / dt
	return v.limit_length(p.NET_CLAIM_H_CAP)


## The stream's own speed over ~100 ms of samples, from the sender's clock (steady, unlike an arrival
## timeline during a burst).
static func _pose_speed(p: Player) -> float:
	if p._pose_buf.size() < 2:
		return 0.0
	var newest: Array = p._pose_buf[-1]
	var oldest: Array = p._pose_buf[0]
	for i in range(p._pose_buf.size() - 1, -1, -1):
		oldest = p._pose_buf[i]
		if int(newest[0]) - int(oldest[0]) >= 100:
			break
	var dt := maxf(float(int(newest[0]) - int(oldest[0])) / 1000.0, 0.05)
	return (newest[1] as Vector3).distance_to(oldest[1] as Vector3) / dt


## Could a pawn have moved `d` in `dt` seconds? Same speed caps as the server's claim check (#B1).
static func claim_reachable_delta(p: Player, d: Vector3, dt: float) -> bool:
	var h := Vector2(d.x, d.z).length()
	return h <= p.NET_CLAIM_H_CAP * dt + p.NET_CLAIM_SLACK and absf(d.y) <= p.NET_CLAIM_V_CAP * dt + p.NET_CLAIM_SLACK


## See net_pos. First pose, the server, or a jump past the travel budget snaps; the rest is buffered.
## On the server a claim is checked first: the client only gets to say where it is (#B1).
static func receive_net_pos(p: Player, v: Vector3, sent_ms: int = 0) -> void:
	if p.multiplayer.is_server() and not p.is_bot:
		p._accept_claim(v)
		return
	push_remote_pose(p, v, sent_ms)


## #B1 server authority over position. Accept a claim only if the pawn could have reached it since the
## last accepted one; otherwise keep our own copy and send a correction (rate limited). Without this a
## modified client could teleport anywhere and shoot from there — and origin_plausible would agree,
## because it compares the shot against the position that same client just claimed.
static func accept_claim(p: Player, v: Vector3) -> void:
	var now := Time.get_ticks_msec()
	var dt := maxf(float(now - p._net_pos_ms) / 1000.0, p.NET_CLAIM_MIN_DT)
	if p.is_dead or p._claim_reachable(v, dt):
		p.position = v
		p._net_pos_ms = now
		return
	# Refused. Reset the window as well, so the budget cannot pile up and turn into a slow teleport.
	p._net_pos_ms = now
	if now - p._corr_ms >= p.NET_CORRECTION_MS and Game.is_networked() and p.peer_id in p.multiplayer.get_peers():
		p._corr_ms = now
		Game.correct_position.rpc_id(p.peer_id, p.peer_id, p.position)


## Could a pawn have gone from where we have it to `v` in `dt` seconds?
static func claim_reachable(p: Player, v: Vector3, dt: float) -> bool:
	return claim_reachable_delta(p, v - p.position, dt)


## LOS: the hands landed a bash and the body snaps to them. Both the server's copy and the owner's
## move here, so the claim check does not read the jump as a teleport and pull the body back.
## Velocity is dropped: the snap is a cut, not a carry. INF-safe (the caller checks).
static func apply_snap(p: Player, v: Vector3) -> void:
	p.global_position = v
	p._net_target = v
	p._net_has = true
	p._pose_buf.clear() # a cut, not a move to interpolate over
	p._net_pos_ms = Time.get_ticks_msec()
	p.velocity = Vector3.ZERO
	if p._style != null:
		p._style.forget_position() # a teleport, so it is never counted as a fall


## Client-side pose of a remote human, drawn from the buffer (#361).
static func smooth_remote(p: Player, delta: float) -> void:
	if p.multiplayer.is_server():
		return
	tick_remote(p, delta)


static func apply_remote_visual(p: Player) -> void:
	p._apply_stance()
	p._apply_team_visual()
	p.body_mesh.visible = not p.is_dead
	p.weapon.visible = not p.is_dead
	p.collision_layer = 0 if p.is_dead else 2
	if p.nametag:
		p.nametag.text = p.display_name
