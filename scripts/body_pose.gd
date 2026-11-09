class_name BodyPose
extends RefCounted
## Pose solver for the B1 crystal body (#164). Pure maths, no nodes: CrystalBody feeds it the blended
## motion state and applies the result. Everything is in BodyMesh space (feet origin, facing -Z).
## Layout: the head sits on Player's head height (so it matches HeadHit, which never moves here), the
## torso hangs from a neck point under it, the detached feet float just above the floor. Dive and wall
## run turn the whole figure (torso, feet) around the neck, so the head stays near the camera/gun.
##
## Input keys (all floats, already smoothed by the caller):
##   crouch 0..1, head_y, phase (gait angle), bob (idle hover angle), walk 0..1, sprint 0..1,
##   air 0..1, dive 0..1, wall -1..1 (sign = wall side, -1 left), dir (Vector3: local move direction)

const NECK_DROP := 0.19 # neck this far under the head centre
const TORSO_HANG := 0.41 # torso centre this far from the neck along the torso axis
const WAIST_HANG := 0.80 # waist seam
const PELVIS_HANG := 0.97 # floating hip shard
const FOOT_Y := 0.07
const FOOT_HALF_W := 0.13
const CROUCH_SPREAD := 0.10
const CROUCH_LEAN := deg_to_rad(40.0)
const CROUCH_TORSO_SCALE := 0.85 # the crouched head (0.78 m) leaves less room than the torso is tall
const SPRINT_LEAN := deg_to_rad(16.0)
const WALK_LEAN := deg_to_rad(6.0)
const DIVE_PITCH := deg_to_rad(-80.0) # feet swing back behind the body
const WALL_ROLL := deg_to_rad(22.0) # top away from the wall, feet toward it
const THROW_PITCH := deg_to_rad(-14.0) # the knife throw leans over the front foot (#25)
const THROW_TWIST := deg_to_rad(-16.0) # and turns the shoulders with the throwing hand
const STRIDE_WALK := 0.22
const STRIDE_SPRINT := 0.16 # extra on top of walking
const LIFT_WALK := 0.10
const LIFT_SPRINT := 0.08


## Part transforms: torso, head, neck_seam, waist_seam, pelvis, feet (Array of 2 Transform3D).
static func solve(p: Dictionary) -> Dictionary:
	var k := clampf(float(p.get("crouch", 0.0)), 0.0, 1.0)
	var head_y := float(p.get("head_y", 1.52))
	var dive := clampf(float(p.get("dive", 0.0)), 0.0, 1.0)
	var air := clampf(float(p.get("air", 0.0)), 0.0, 1.0) * (1.0 - dive)
	var wall := clampf(float(p.get("wall", 0.0)), -1.0, 1.0)
	var gait := 1.0 - maxf(air, dive)
	var walk := clampf(float(p.get("walk", 0.0)), 0.0, 1.0) * gait
	var sprint := clampf(float(p.get("sprint", 0.0)), 0.0, 1.0) * gait
	var phase := float(p.get("phase", 0.0))
	var bob := sin(float(p.get("bob", 0.0))) * 0.015 * (1.0 - walk)
	var dir: Vector3 = p.get("dir", Vector3.FORWARD)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.FORWARD

	var neck := Vector3(0, head_y - NECK_DROP + bob, 0)
	var lean := WALK_LEAN * walk + SPRINT_LEAN * sprint + CROUCH_LEAN * k + 0.10 * air
	lean *= 1.0 - dive
	var squash := lerpf(1.0, CROUCH_TORSO_SCALE, k * (1.0 - dive))
	var torso_basis := Basis(Vector3.RIGHT, -lean) * Basis.from_scale(Vector3(1, squash, 1))
	var up := torso_basis * Vector3.UP
	# Whole-figure turn around the neck: dive pitch, wall-run roll, and the landing roll's forward flip
	# (#205 - a rolling player used to stand upright in every view but their own camera).
	var flip := float(p.get("flip", 0.0))
	# The knife throw (#25): the torso turns away from the throwing side and pitches over the front
	# foot. Small numbers, because the figure has no arms of its own - the hands follow the weapon.
	var thr := clampf(float(p.get("throw", 0.0)), 0.0, 1.0)
	var rig := Basis(Vector3.BACK, WALL_ROLL * wall) \
			* Basis(Vector3.RIGHT, DIVE_PITCH * dive + flip + THROW_PITCH * thr) \
			* Basis(Vector3.UP, THROW_TWIST * thr)

	var out := {}
	out["torso"] = Transform3D(rig * torso_basis, neck + rig * (-up * TORSO_HANG))
	out["neck_seam"] = Transform3D(rig * torso_basis, neck + rig * (up * 0.02))
	out["waist_seam"] = Transform3D(rig * torso_basis, neck + rig * (-up * WAIST_HANG))
	out["pelvis"] = Transform3D(rig * torso_basis, neck + rig * (-up * PELVIS_HANG))
	out["head"] = Transform3D(rig * Basis(Vector3.RIGHT, -lean * 0.3), neck + rig * Vector3(0, NECK_DROP, 0))

	var feet: Array[Transform3D] = []
	var stride := STRIDE_WALK * walk + STRIDE_SPRINT * sprint
	var lift := LIFT_WALK * walk + LIFT_SPRINT * sprint
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var a := phase + PI * i
		var f := Vector3(side * (FOOT_HALF_W + CROUCH_SPREAD * k), FOOT_Y + bob * 0.5, 0)
		f += dir * stride * sin(a)
		f.y += lift * maxf(0.0, cos(a))
		f.z += (-0.12 if i == 0 else 0.10) * k # crouch: one foot forward, one back
		f += Vector3(0, 0.22 + 0.06 * i, -0.10 if i == 0 else 0.12) * air # jump: tuck, split
		f.x += side * 0.08 * dive # dive: trail slightly apart
		f = neck + rig * (f - neck)
		var tilt := Basis(Vector3.RIGHT, -PI / 2) # foot mesh axis +Y → forward
		var toe := Basis(Vector3.RIGHT, (0.5 * sin(a) * lift / maxf(LIFT_WALK, 0.01)))
		feet.append(Transform3D(rig * toe * tilt, f))
	out["feet"] = feet
	return out
