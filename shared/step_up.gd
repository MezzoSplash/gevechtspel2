class_name StepUp
extends RefCounted
## Walks a grounded capsule over small lips (a slab seam, a curb, a ramp edge) instead of stopping.
## Only runs on the floor, so air strafing and surfing never see it. A landing must be real floor
## (not a surf face) and no higher than MAX_HEIGHT. Players and bots use the same call.

const MAX_HEIGHT := 0.32
const MIN_HEIGHT := 0.015
const PROBE := 0.12 # how far past the lip the capsule must fit (m)


## Call right after move_and_slide(). `pre_velocity` is the velocity before it, `was_on_floor`
## whether the body stood on the floor before it. Returns the height climbed (0 = nothing done).
static func try_step(body: CharacterBody3D, pre_velocity: Vector3, was_on_floor: bool, delta: float) -> float:
	if not was_on_floor or pre_velocity.y > 0.5:
		return 0.0
	if not body.is_on_wall():
		return 0.0
	var horiz := Vector3(pre_velocity.x, 0.0, pre_velocity.z)
	var speed := horiz.length()
	if speed < 0.5:
		return 0.0
	var dir := horiz / speed
	# Only when the wall actually faces the move (not a wall we slide along).
	var wn := body.get_wall_normal()
	var wn_h := Vector3(wn.x, 0.0, wn.z)
	if wn_h.length_squared() < 0.0001 or wn_h.normalized().dot(dir) > -0.3:
		return 0.0
	var start := body.global_transform
	var up := Vector3.UP * MAX_HEIGHT
	var col := KinematicCollision3D.new()
	# 1. Up. A ceiling right above shortens the step.
	var lifted := start
	if body.test_move(start, up, col, body.safe_margin):
		lifted.origin += up * maxf(col.get_travel().length() / MAX_HEIGHT - 0.01, 0.0)
	else:
		lifted.origin += up
	var rise := lifted.origin.y - start.origin.y
	if rise < MIN_HEIGHT:
		return 0.0
	# 2. Forward: the rest of this frame's move, at least PROBE so the capsule clears the edge.
	var fwd := dir * maxf(speed * delta, PROBE)
	var moved := lifted
	if body.test_move(lifted, fwd, col, body.safe_margin):
		return 0.0 # still a wall at this height: real cover, not a lip
	moved.origin += fwd
	# 3. Down onto the top of the lip.
	var down := Vector3.DOWN * (rise + 0.02)
	if not body.test_move(moved, down, col, body.safe_margin):
		return 0.0 # nothing under us: that is a drop, let normal movement handle it
	var n := col.get_normal()
	if n.y < cos(body.floor_max_angle) - 0.001:
		return 0.0 # landed on a surf face or a steep side
	var landed := moved.origin + col.get_travel()
	var climb := landed.y - start.origin.y
	if climb < MIN_HEIGHT or climb > MAX_HEIGHT + 0.001:
		return 0.0
	body.global_position = landed
	body.velocity = Vector3(pre_velocity.x, 0.0, pre_velocity.z)
	body.apply_floor_snap()
	return climb
