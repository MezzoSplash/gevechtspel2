class_name BotNav
extends RefCounted
## A bot's feet (#317 slice 3, from scripts/bot_brain.gd): steering along the path, the soft separation
## push, stuck detection and the unstick sidestep, the strafe-side probe and the ledge hop. Static on the
## brain like bot_cover: the state (_wants_move, _unstick_*, _strafe_*, _stuck_*) stays on BotBrain and
## this is called with the brain as `b`.
##
## The rng calls here (randf for the unstick angle, randf_range for the strafe hold) sit at exactly the
## tick position they had before the move: order preserved, so the seeded replay is unchanged.


## Stuck: no real progress since the last check while the bot wants to move, and no unstick running.
static func track_stuck(b: BotBrain, delta: float) -> void:
	b._stuck_pulse = false
	b._unstick_left = maxf(b._unstick_left - delta, 0.0)
	b._stuck_t += delta
	if b._stuck_t < BotBrain.STUCK_CHECK:
		return
	b._stuck_t = 0.0
	var moved := b.pawn.global_position.distance_to(b._stuck_pos)
	b._stuck_pos = b.pawn.global_position
	if moved < BotBrain.STUCK_DIST and b._wants_move and b._unstick_left <= 0.0:
		b._stuck_pulse = true


## Soft push away from pawns that are too close, so bots do not stack up in doorways.
static func separation(b: BotBrain) -> Vector3:
	var push := Vector3.ZERO
	for p in Game.players(): # #272: one roster per tick, not a group array per bot
		if p == b.pawn or p.is_dead:
			continue
		var away := b.pawn.global_position - p.global_position
		away.y = 0.0
		var d := away.length()
		if d >= BotBrain.SEPARATION_R:
			continue
		if d < 0.01:
			away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			d = 0.01
		push += away.normalized() * (1.0 - d / BotBrain.SEPARATION_R)
	return push


## Four random directions, the first walkable one becomes a short forced sidestep.
static func pick_unstick(b: BotBrain) -> void:
	for _i in 4:
		var a := randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		if side_open(b, dir):
			b._unstick_dir = dir
			b._unstick_left = BotBrain.UNSTICK_TIME
			return
	b._unstick_left = 0.0


## Prefer `side * sign` when that metre is walkable. Both closed: stand and shoot.
static func pick_strafe_side(b: BotBrain, side: Vector3) -> void:
	var prefer := side * b._strafe_sign
	var open_prefer := side_open(b, prefer)
	if not open_prefer and side_open(b, -prefer):
		b._strafe_sign *= -1.0
		open_prefer = true
	if open_prefer:
		b._strafe_hold = randf_range(b.style.strafe_hold_min, b.style.strafe_hold_max)
		b._strafe_pause = 0.0
	else:
		b._strafe_hold = 0.0
		b._strafe_pause = randf_range(BotBrain.STRAFE_PAUSE_MIN, BotBrain.STRAFE_PAUSE_MAX)


## True when a step along dir is not a wall and still has floor under it.
## `reach` is how far ahead to look. Picking a side looks further than the step that cuts a commit.
static func side_open(b: BotBrain, dir: Vector3, reach: float = BotBrain.STRAFE_PROBE) -> bool:
	dir.y = 0.0
	if dir.length_squared() < 0.0001 or b.pawn == null:
		return false
	dir = dir.normalized()
	var space := b.pawn.get_world_3d().direct_space_state
	var chest := b.pawn.global_position + Vector3.UP * 0.9
	var wall := PhysicsRayQueryParameters3D.create(chest, chest + dir * reach)
	wall.collision_mask = BotBrain.WORLD_MASK
	if not space.intersect_ray(wall).is_empty():
		return false
	var foot := b.pawn.global_position + dir * reach + Vector3.UP * 0.4
	var floor_q := PhysicsRayQueryParameters3D.create(foot, foot + Vector3.DOWN * BotBrain.STRAFE_FLOOR)
	floor_q.collision_mask = BotBrain.WORLD_MASK
	var hit := space.intersect_ray(floor_q)
	if not hit.has("normal"):
		return false
	var slope := rad_to_deg(acos(clampf((hit.normal as Vector3).dot(Vector3.UP), -1.0, 1.0)))
	# A few degrees of slack: a 46° ramp the navmesh accepts should not read as a wall.
	return slope <= BotBrain.MAX_STEP_SLOPE + 4.0


## Height of the lip in front of `wish`, or -1 when there is nothing to jump.
## Chest ray finds a face steeper than a walkable ramp. A second ray, from above
## the head down onto the far side, has to land on a top we can actually clear.
static func ledge_climb(b: BotBrain, wish: Vector3) -> float:
	if b.pawn == null:
		return -1.0
	wish.y = 0.0
	if wish.length_squared() < 0.0001:
		return -1.0
	var dir := wish.normalized()
	var space := b.pawn.get_world_3d().direct_space_state
	var origin := b.pawn.global_position
	var chest := origin + Vector3.UP * 0.45
	var wall_q := PhysicsRayQueryParameters3D.create(chest, chest + dir * 0.85)
	wall_q.collision_mask = BotBrain.WORLD_MASK
	wall_q.exclude = [b.pawn.get_rid()]
	var wall := space.intersect_ray(wall_q)
	if wall.is_empty() or not wall.has("normal"):
		return -1.0
	var slope := rad_to_deg(acos(clampf((wall.normal as Vector3).dot(Vector3.UP), -1.0, 1.0)))
	if slope <= BotBrain.MAX_STEP_SLOPE + 4.0:
		return -1.0
	var head_q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 1.0, origin + Vector3.UP * 2.1)
	head_q.collision_mask = BotBrain.WORLD_MASK
	head_q.exclude = [b.pawn.get_rid()]
	if not space.intersect_ray(head_q).is_empty():
		return -1.0
	var from := origin + Vector3.UP * 1.55 + dir * 0.25
	var to := origin + dir * 1.15 + Vector3.UP * 0.15
	var top_q := PhysicsRayQueryParameters3D.create(from, to)
	top_q.collision_mask = BotBrain.WORLD_MASK
	top_q.exclude = [b.pawn.get_rid()]
	var top := space.intersect_ray(top_q)
	if not top.has("normal") or not top.has("position"):
		return -1.0
	if (top.normal as Vector3).dot(Vector3.UP) < 0.7:
		return -1.0
	var climb := (top.position as Vector3).y - origin.y
	if climb < BotBrain.JUMP_CLEAR_MIN or climb > BotBrain.JUMP_CLEAR_MAX:
		return -1.0
	return climb


static func try_jump_ledge(b: BotBrain, wish: Vector3) -> bool:
	if b.pawn == null or not b.pawn.is_on_floor():
		return false
	if ledge_climb(b, wish) < 0.0:
		return false
	b.pawn.velocity.y = Player.JUMP_SPEED
	return true


## Steer the pawn along the path (or straight at `dest` when the navmesh has nothing useful).
static func steer_to(b: BotBrain, dest: Vector3, speed: float, delta: float, use_nav: bool = true) -> void:
	var dir := Vector3.ZERO
	if use_nav and b.agent and not b.agent.is_navigation_finished():
		var next := b.agent.get_next_path_position()
		dir = next - b.pawn.global_position
		dir.y = 0.0
	# Also when the next path point is (nearly) straight above us (navmesh a bit higher than the feet, e.g.
	# beside a low ledge): the agent never reaches it and the bot would stand still forever.
	if dir.length() < 0.12:
		dir = dest - b.pawn.global_position
		dir.y = 0.0
	var wish := Vector3.ZERO
	if dir.length() >= 0.12:
		wish = dir.normalized()
	if b._unstick_left > 0.0:
		wish = b._unstick_dir
	b._wants_move = wish.length_squared() > 0.0001
	var push := separation(b) * 1.2
	if push.length_squared() > 0.0001:
		wish += push
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
	var on_floor := b.pawn.is_on_floor()
	var horiz := Vector3(b.pawn.velocity.x, 0.0, b.pawn.velocity.z)
	if on_floor:
		horiz = b.pawn._friction(horiz, delta)
		horiz = b.pawn._accelerate(horiz, wish, speed * b.pawn.gun_speed_mult(), Player.GROUND_ACCEL, delta)
	else:
		horiz = b.pawn._accelerate(horiz, wish, Player.WALK_SPEED, Player.BOT_AIR_ACCEL, delta)
	b.pawn.velocity.x = horiz.x
	b.pawn.velocity.z = horiz.z
	# Requested sprint, not the speed we have yet: the pose and the spread follow the
	# intent. Fight passes STRAFE_SPEED, so a strafe does not count as sprinting.
	b.pawn.is_sprinting = on_floor and b._wants_move and speed >= Player.SPRINT_SPEED - 0.05
	if on_floor and b._wants_move:
		try_jump_ledge(b, wish)
