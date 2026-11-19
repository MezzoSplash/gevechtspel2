class_name PawnNet
extends RefCounted
## How a pawn lives on other machines (#316): a bot's pose from sync_bot_poses, the nametag and its line
## of sight, the synced position with the server's claim check (#B1) and its corrections, the LOS snap,
## a remote human's glide and a remote pawn's visuals. Static on the pawn `p`, like Movement; Player keeps
## the synced properties, the state and its old function names, so nothing on the wire changes.


## Client-side bot transform from Game.sync_bot_poses (Synchronizer is off for bots).
## `stance` (optional, newer servers): [crouch, move_fx], so remote bots crouch, dive and wall-run visibly.
static func apply_network_pose(p: Player, pos: Vector3, yaw: float, pitch: float, stance: Array = []) -> void:
	p.global_position = pos
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


## See net_pos. First pose, the server, or a jump past NET_SNAP_M (respawn) snaps.
## On the server a claim is checked first: the client only gets to say where it is (#B1).
static func receive_net_pos(p: Player, v: Vector3) -> void:
	if p.multiplayer.is_server() and not p.is_bot:
		p._accept_claim(v)
		return
	var smooth := p.is_inside_tree() and p._net_has and not p.multiplayer.is_server()
	p._net_target = v
	p._net_has = true
	if not smooth or v.distance_to(p.position) > p.NET_SNAP_M:
		p.position = v


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
		Game.correct_position.rpc_id(p.peer_id, p.position)


## Could a pawn have gone from where we have it to `v` in `dt` seconds?
static func claim_reachable(p: Player, v: Vector3, dt: float) -> bool:
	var d := v - p.position
	var h := Vector2(d.x, d.z).length()
	return h <= p.NET_CLAIM_H_CAP * dt + p.NET_CLAIM_SLACK and absf(d.y) <= p.NET_CLAIM_V_CAP * dt + p.NET_CLAIM_SLACK


## LOS: the hands landed a bash and the body snaps to them. Both the server's copy and the owner's
## move here, so the claim check does not read the jump as a teleport and pull the body back.
## Velocity is dropped: the snap is a cut, not a carry. INF-safe (the caller checks).
static func apply_snap(p: Player, v: Vector3) -> void:
	p.global_position = v
	p._net_target = v
	p._net_has = true
	p._net_pos_ms = Time.get_ticks_msec()
	p.velocity = Vector3.ZERO
	if p._style != null:
		p._style.forget_position() # a teleport, so it is never counted as a fall


## Client-side glide of a remote human toward _net_target (frame-rate independent).
## A local teleport of the pawn (e.g. a respawn RPC) re-bases the target instead of being pulled back.
static func smooth_remote(p: Player, delta: float) -> void:
	if not p._net_has or p.multiplayer.is_server():
		return
	if p.position.distance_to(p._net_target) > p.NET_SNAP_M:
		p._net_target = p.position
		return
	p.position = p._net_target + (p.position - p._net_target) * exp(-delta / p.NET_SMOOTH_S)


static func apply_remote_visual(p: Player) -> void:
	p._apply_stance()
	p._apply_team_visual()
	p.body_mesh.visible = not p.is_dead
	p.weapon.visible = not p.is_dead
	p.collision_layer = 0 if p.is_dead else 2
	if p.nametag:
		p.nametag.text = p.display_name
