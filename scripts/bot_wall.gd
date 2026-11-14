class_name BotWall
extends RefCounted
## Finds a wall a bot can run along, from raycasts alone: no per-map data, so a new map or a moved wall
## needs nothing. Pure and static (a physics space in, a plan out) so a check can drive it without a pawn.
##
## A wall counts when it is as vertical as `Movement.find_wall` needs (`Player.WALLRUN_MAX_NY`), runs the way the
## bot is already heading (its tangent is the heading projected onto the face), is `MIN_LEN` long and clear along
## the run line, reaches `MIN_HEIGHT` above the feet, and has walkable floor under the run line, so a run along
## a roof edge over a drop is never started.

const MASK := 1 # arena only; pawns are layer 2
const RANGE := 6.0 # m: how far ahead a scan ray looks
## Scan rays sit this far off the heading, to each side: a wall at a shallow angle and one beside us.
const SCAN_ANGLES: Array[float] = [0.61, 1.31] # 35° and 75°
const CHEST := 0.9 # m above the feet
const MIN_LEN := 7.0 # m of face along the run (a run lasts WALLRUN_TIME 1.25 s at sprint: about 11 m)
const MIN_HEIGHT := 2.0 # m above the feet the face must still reach
const OFFSET := 0.7 # m: the run line sits this far off the face
const MIN_ALONG := 0.6 # |heading projected on the face|: below this the bot is running into the wall, not along it
const ENTRY_ANGLE := 0.61 # rad: the bot meets the face at this angle (35°); along speed stays 0.82 of its speed
const FLOOR_DROP := 14.0 # m: walkable floor must be within this far below a point we run or land over
const WALKABLE_NY := 0.7 # cos 45°, same as the navmesh's agent_max_slope


## The nearest runnable wall ahead of `origin` (feet), or {} when there is none. `heading` is flat or not.
## {"n": outward face normal (flat), "along": run direction (flat), "point": where the scan ray hit,
##  "dist": metres to it}.
static func find(space: PhysicsDirectSpaceState3D, origin: Vector3, heading: Vector3, exclude: Array[RID]) -> Dictionary:
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		return {}
	heading = heading.normalized()
	var chest := origin + Vector3.UP * CHEST
	var best := {}
	var best_d := INF
	for side in [-1.0, 1.0]:
		for a in SCAN_ANGLES:
			var dir := heading.rotated(Vector3.UP, side * a)
			var hit := _ray(space, chest, chest + dir * RANGE, exclude)
			if hit.is_empty():
				continue
			var d := origin.distance_to(hit.position as Vector3)
			if d >= best_d:
				continue
			var plan := _plan(space, origin, heading, hit, exclude)
			if plan.is_empty():
				continue
			best = plan
			best_d = d
	return best


## Direction to leave the floor in: along the wall, turned into it by ENTRY_ANGLE, so the body touches the face
## with speed left to run on (find_wall reads the touch, Movement.tick_wallrun starts the run).
static func entry_dir(plan: Dictionary) -> Vector3:
	var along: Vector3 = plan.along
	var n: Vector3 = plan.n
	return (along * cos(ENTRY_ANGLE) - n * sin(ENTRY_ANGLE)).normalized()


## Walkable floor under `pos`, within FLOOR_DROP. Used for the run line and before a wall jump: a jump off a
## roof wall into the street is a fall death on Skyline.
static func floor_below(space: PhysicsDirectSpaceState3D, pos: Vector3, exclude: Array[RID]) -> bool:
	var hit := _ray(space, pos + Vector3.UP * 0.5, pos + Vector3.DOWN * FLOOR_DROP, exclude)
	return not hit.is_empty() and (hit.normal as Vector3).y >= WALKABLE_NY


static func _plan(space: PhysicsDirectSpaceState3D, origin: Vector3, heading: Vector3, hit: Dictionary, exclude: Array[RID]) -> Dictionary:
	var n: Vector3 = hit.normal
	if absf(n.y) >= Player.WALLRUN_MAX_NY:
		return {}
	var nh := Vector3(n.x, 0.0, n.z)
	if nh.length_squared() < 0.0001:
		return {}
	nh = nh.normalized()
	var along := heading - nh * heading.dot(nh)
	if along.length() < MIN_ALONG:
		return {}
	along = along.normalized()
	var p: Vector3 = hit.position
	var line := Vector3(p.x, origin.y + CHEST, p.z) + nh * OFFSET # start of the run line, off the face
	# The face has to go on: three probes into it along the run, chest height, each landing on a flat face.
	for f in [0.5, 1.0]:
		var at: Vector3 = line + along * MIN_LEN * f
		var wall := _ray(space, at, at - nh * (OFFSET + 0.6), exclude)
		if wall.is_empty() or absf((wall.normal as Vector3).y) >= Player.WALLRUN_MAX_NY:
			return {}
	# ... and it has to be tall enough that the body keeps touching it while it sinks.
	var tall := line + Vector3.UP * (MIN_HEIGHT - CHEST)
	if _ray(space, tall, tall - nh * (OFFSET + 0.6), exclude).is_empty():
		return {}
	# The run line itself is clear (a crate or a pillar on it would end the run on a bump).
	if not _ray(space, line, line + along * MIN_LEN, exclude).is_empty():
		return {}
	# Floor under the start, the middle and the end of the run.
	for f in [0.0, 0.5, 1.0]:
		if not floor_below(space, Vector3(line.x, origin.y, line.z) + along * MIN_LEN * f, exclude):
			return {}
	return {"n": nh, "along": along, "point": p, "dist": origin.distance_to(p)}


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	q.exclude = exclude
	return space.intersect_ray(q)
