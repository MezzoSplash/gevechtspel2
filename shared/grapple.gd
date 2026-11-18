class_name Grapple
extends RefCounted
## The grapple: a hard pull toward a point on the world, held on a key, released with the speed it
## built. One job, off the network (the pawn syncs `grapple_at` itself), reachable through the pawn's
## own function names (`Player.start_grapple`, `Player.is_grappling`), like StyleTrack.
##
## Feel: the press fires a ray from the eye; a hit anchors the rope and the pull starts at once. While
## the key is held the body accelerates toward the anchor at PULL_ACCEL up to PULL_SPEED, the sideways
## part of the velocity bleeds off at SIDE_DAMP so it is a pull and not an orbit, and gravity still
## acts (the pull outweighs it). Letting go, arriving, losing the line or running out of PULL_TIME ends
## the pull and keeps the velocity: the release is the move. A wallrun or a dive takes over from it.

## Rope length: far enough to cross a plaza, short of sniper lines.
const RANGE := 32.0
const PULL_ACCEL := 55.0 # m/s² toward the anchor (gravity is 9.8: the pull wins, upward too)
const PULL_SPEED := 22.0 # m/s: the pull adds no speed along the rope past this
const SIDE_DAMP := 2.2 # 1/s: sideways velocity fades so the line is straight
const PULL_TIME := 1.6 # s: the longest pull (32 m at 22 m/s is about 1.5 s)
const ARRIVE := 1.8 # m from the anchor: the pull is over, you carry through
const COOLDOWN := 3.0 # s from the start of a pull to the next
const MISS_COOLDOWN := 0.35 # s after a press that hit nothing: no spam, but a miss is not punished
const GROUND_LIFT := 4.5 # m/s up when the pull starts on the floor, so friction does not eat it
const CHEST := 1.1 # m above the feet: where the rope pulls
## The rope's line of sight is traced from about the eye, where the anchor ray came from: traced from
## the chest, a low wall the eye saw over cut the rope on the first tick of the pull.
const LINE_FROM := 1.5
const CUT_GRACE := 0.12 # s: the start of a pull is never cut (the body is still lifting off)
const LINE_SLACK := 0.6 # m: a wall this close to the anchor does not cut the line (the anchor is on it)
const WORLD_MASK := 1

var active := false
var anchor := Vector3.ZERO
var normal := Vector3.UP
var t := 0.0 # s into this pull
var cd := 0.0 # s until the next press may fire


## The anchor for a press: the first world hit along `dir` within RANGE, or {} for a miss.
static func find_anchor(space: PhysicsDirectSpaceState3D, eye: Vector3, dir: Vector3, exclude: Array[RID]) -> Dictionary:
	if dir.length_squared() < 1e-6:
		return {}
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir.normalized() * RANGE)
	q.collision_mask = WORLD_MASK
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"point": hit.position, "normal": hit.normal}


## One tick of pull on `vel` for a body whose chest is at `chest`. Pure: returns the new velocity.
static func pull(vel: Vector3, chest: Vector3, at: Vector3, delta: float) -> Vector3:
	var to := at - chest
	var d := to.length()
	if d < 1e-4:
		return vel
	var dir := to / d
	var along := vel.dot(dir)
	var side := vel - dir * along
	side *= exp(-SIDE_DAMP * delta)
	if along < PULL_SPEED:
		along = minf(along + PULL_ACCEL * delta, PULL_SPEED)
	return dir * along + side


## A press: anchor if the ray hits, cooldown either way. True when a pull started.
func try_start(space: PhysicsDirectSpaceState3D, eye: Vector3, dir: Vector3, exclude: Array[RID]) -> bool:
	if active or cd > 0.0:
		return false
	var hit := find_anchor(space, eye, dir, exclude)
	if hit.is_empty():
		cd = MISS_COOLDOWN
		return false
	begin(hit.point, hit.normal)
	return true


## Anchor at `at` directly (the press, and the checks).
func begin(at: Vector3, n: Vector3 = Vector3.UP) -> void:
	active = true
	anchor = at
	normal = n
	t = 0.0
	cd = COOLDOWN


## Ends the pull; the velocity is left as it is.
func release() -> void:
	active = false
	t = 0.0


func tick_cooldown(delta: float) -> void:
	cd = maxf(cd - delta, 0.0)


## Should the pull end this tick? `feet` is the body's origin, `held` the key, `space` traces the line
## (null skips that test).
func should_end(feet: Vector3, held: bool, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> bool:
	if not active:
		return false
	var chest := feet + Vector3.UP * CHEST
	if not held or t >= PULL_TIME or chest.distance_to(anchor) <= ARRIVE:
		return true
	if space != null and t >= CUT_GRACE:
		var from := feet + Vector3.UP * LINE_FROM
		var to := anchor - from
		var d := to.length()
		if d > LINE_SLACK:
			var q := PhysicsRayQueryParameters3D.create(from, from + to / d * (d - LINE_SLACK))
			q.collision_mask = WORLD_MASK
			q.exclude = exclude
			if not space.intersect_ray(q).is_empty():
				return true # something came between you and the anchor: the rope is cut
	return false


func reset() -> void:
	active = false
	t = 0.0
	cd = 0.0
