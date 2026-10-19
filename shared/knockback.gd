class_name Knockback
## Blast knockback (frag, RC-XD). Server/offline only: it works out the push and hands it to
## whoever simulates the body. Players move on their own machine, so the push is sent to the
## owner (Game.sync_knockback); bots and the host's own pawn are pushed directly. RC-XD cars:
## the authority car is pushed, and the driver's predicted copy is told (Game.sync_rc_kick).

const GRENADE_POWER := 14.0 # m/s at the blast centre
const RCXD_POWER := 11.0
const CAR_POWER := 1.0 # share of the power a car takes (it is small and light)
const SELF_MULT := 0.75 # your own blast pushes you a bit less
const MIN_UP := 0.35 # the push always has this much upward share: a blast lifts, it does not slide
const MAX_PUSH := 12.0 # m/s hard cap on one impulse
const CAR_MAX := 9.0


static func impulse_for(pos: Vector3, body_pos: Vector3, radius: float, power: float, mult: float, cap: float) -> Vector3:
	var to := body_pos - pos
	var dist := to.length()
	if dist >= radius:
		return Vector3.ZERO
	var f := 1.0 - dist / radius
	var dir := to / dist if dist > 0.05 else Vector3.UP
	dir.y = maxf(dir.y, MIN_UP)
	dir = dir.normalized()
	return dir * minf(power * f * mult, cap)


static func blast(pos: Vector3, radius: float, power: float, source_peer: int, source_team: int, skip_car: Node = null) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for n in tree.get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead:
			continue
		var own := p.peer_id == source_peer
		if not own and p.team_id == source_team and not Game.is_ffa():
			continue
		var centre := p.global_position + Vector3(0.0, 1.0, 0.0)
		if not _reaches(p.get_world_3d().direct_space_state, pos, p.global_position, [1.0, 1.6, 0.3]):
			continue
		var imp := impulse_for(pos, centre, radius, power, SELF_MULT if own else 1.0, MAX_PUSH)
		if imp != Vector3.ZERO:
			_push_player(p, imp)
	for n in tree.get_nodes_in_group("rc_xd"):
		var c := n as RcXd
		if c == null or c == skip_car or not c.authority_sim:
			continue
		if not _reaches(c.get_world_3d().direct_space_state, pos, c.global_position, [0.0, 0.3]):
			continue
		var imp := impulse_for(pos, c.global_position, radius, power * CAR_POWER, 1.0, CAR_MAX)
		if imp == Vector3.ZERO:
			continue
		c.add_kick(imp)
		if Game.is_networked() and c.owner_peer > 1:
			Game.sync_rc_kick.rpc_id(c.owner_peer, c.net_id, imp)


static func _push_player(p: Player, imp: Vector3) -> void:
	if p.is_bot or not Game.is_networked() or p.peer_id == Game.multiplayer.get_unique_id():
		p.add_knockback(imp)
	else:
		Game.sync_knockback.rpc_id(p.peer_id, p.peer_id, imp)


static func _reaches(space: PhysicsDirectSpaceState3D, pos: Vector3, at: Vector3, heights: Array) -> bool:
	for h in heights:
		var q := PhysicsRayQueryParameters3D.create(pos, at + Vector3(0.0, h, 0.0))
		q.collision_mask = 1
		if space.intersect_ray(q).is_empty():
			return true
	return false
