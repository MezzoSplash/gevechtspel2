class_name PawnNet
extends RefCounted
## How a pawn lives on other machines (#316): a bot's pose from sync_bot_poses, the nametag and its line
## of sight, the synced position with the server's claim check (#B1) and its corrections, the LOS snap,
## a remote human's glide and a remote pawn's visuals. Static on the pawn `p`, like Movement; Player keeps
## the synced properties, the state and its old function names, so nothing on the wire changes.


## Client-side bot transform from Game.sync_bot_poses (Synchronizer is off for bots).
## `stance` (optional, newer servers): [crouch, move_fx], so remote bots crouch, dive and wall-run visibly.
static func apply_network_pose(p: Player, pos: Vector3, yaw: float, pitch: float, stance: Array = []) -> void:
	push_remote_pose(p, pos) # #361: the drawn position comes from the buffer, the rest is immediate
	p.rotation.y = yaw
	p._yaw = yaw
	p._pitch = pitch
	if p.head:
		p.head.rotation.x = pitch
	p.velocity = Vector3.ZERO
	if stance.size() >= 2:
		p.crouch = clampf(float(stance[0]), 0.0, 1.0)
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


## --- #361: remote pose interpolation ---
## Poses of remote humans ($Sync) and remote bots (sync_bot_poses) wait in a small buffer and are drawn
## slightly behind the newest one, so a lost or late packet is covered by the next pose instead of the
## pawn freezing and then jumping across the map. The delay follows the measured gap between arrivals:
## on a LAN it stays at DELAY_MIN_MS (about what the old glide cost), on a lossy link it grows to
## DELAY_MAX_MS. `Game.net_delay_ms` holds the value the whole machine uses, so LagComp stays honest.
const DELAY_MIN_MS := 55
const DELAY_MAX_MS := 150
## A stall longer than this stops the pawn where it is instead of throwing it forward.
const EXTRAP_MAX_MS := 150
const BUFFER_MAX := 60 # ~2 s of poses at 30 Hz
const GAP_DECAY := 0.98 # per arrival: the delay falls back within a second or two of a clean link


## A pose arrived for `p` (client side). `at_ms` is its arrival time; negative means now (checks pass it).
## A jump the server would refuse as a claim is a teleport (respawn, LOS snap, a correction), so that one
## is drawn at once instead of sliding the pawn over the map.
static func push_remote_pose(p: Player, pos: Vector3, at_ms: int = -1) -> void:
	var t := Time.get_ticks_msec() if at_ms < 0 else at_ms
	if p._pose_buf.is_empty():
		p.position = pos
	else:
		var last: Array = p._pose_buf[-1]
		_note_gap(t - int(last[0]))
		var dt := maxf(float(t - int(last[0])) / 1000.0, p.NET_CLAIM_MIN_DT)
		if not claim_reachable_delta(p, pos - (last[1] as Vector3), dt):
			p._pose_buf.clear()
			p.position = pos
	p._pose_buf.append([t, pos])
	while p._pose_buf.size() > BUFFER_MAX:
		p._pose_buf.pop_front()


## The interpolation delay this machine is using right now, in ms, from the gaps it has been seeing.
static func _note_gap(gap_ms: int) -> void:
	var peak := maxf(Game._net_pose_peak_ms * GAP_DECAY, float(gap_ms))
	Game._net_pose_peak_ms = peak
	Game.net_delay_ms = clampi(int(1.5 * peak), DELAY_MIN_MS, DELAY_MAX_MS)


## Client: draw remote pawn `p` at the buffered pose `Game.net_delay_ms` behind the newest one (#361).
## `at_ms` is the clock to render at; negative means now (checks pass their own timeline).
static func tick_remote(p: Player, delta: float, at_ms: int = -1) -> void:
	if p._pose_buf.is_empty():
		return
	var from_pos := p.position
	var now := Time.get_ticks_msec() if at_ms < 0 else at_ms
	var at := float(now - Game.net_delay_ms)
	var newest: Array = p._pose_buf[-1]
	var out := p.position
	if at >= float(newest[0]):
		# Nothing newer arrived: carry the last motion for a moment, then stand still.
		var ext := minf(at - float(newest[0]), EXTRAP_MAX_MS) / 1000.0
		out = (newest[1] as Vector3) + _pose_velocity(p) * ext
	else:
		# Drop the samples the render time has passed, keeping one behind it for the lerp.
		while p._pose_buf.size() > 2 and float(p._pose_buf[1][0]) <= at:
			p._pose_buf.pop_front()
		var found := false
		for i in range(p._pose_buf.size() - 1):
			var s0: Array = p._pose_buf[i]
			var s1: Array = p._pose_buf[i + 1]
			if at >= float(s0[0]) and at <= float(s1[0]):
				var span := maxf(float(s1[0]) - float(s0[0]), 0.001)
				out = (s0[1] as Vector3).lerp(s1[1] as Vector3, (at - float(s0[0])) / span)
				found = true
				break
		if not found:
			# Behind every sample we still hold (a stall): take the oldest instead of guessing.
			out = p._pose_buf[0][1]
	p.position = out
	# Jitter reorders poses, so a sample can sit behind the previous one. Limit how far the drawn pawn
	# may move in one frame to the speed of the stream plus a margin: the path stays continuous instead
	# of zig-zagging, and on a clean link nothing is limited.
	var lim := (_pose_speed(p) + 3.0) * maxf(delta, 0.001)
	if lim > 0.0 and out.distance_to(from_pos) > lim:
		var dir := (out - from_pos).normalized()
		if dir != Vector3.ZERO:
			p.position = from_pos + dir * lim


## Metres per second over the last two poses, capped at what the server accepts as movement.
static func _pose_velocity(p: Player) -> Vector3:
	if p._pose_buf.size() < 2:
		return Vector3.ZERO
	var a: Array = p._pose_buf[-2]
	var b: Array = p._pose_buf[-1]
	var dt := maxf(float(int(b[0]) - int(a[0])) / 1000.0, 0.001)
	var v: Vector3 = ((b[1] as Vector3) - (a[1] as Vector3)) / dt
	return v.limit_length(p.NET_CLAIM_H_CAP)


## The stream's own speed over ~100 ms of samples. Steadier than two neighbouring poses, which jitter
## reorders: the frame limiter must not read a reordered pair as a 100 m/s dash (#361).
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
static func receive_net_pos(p: Player, v: Vector3) -> void:
	if p.multiplayer.is_server() and not p.is_bot:
		p._accept_claim(v)
		return
	push_remote_pose(p, v)


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
