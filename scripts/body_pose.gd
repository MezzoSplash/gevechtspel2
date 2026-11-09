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
const FOOT_Y := 0.07
const FOOT_HALF_W := 0.13
const CROUCH_SPREAD := 0.10
const CROUCH_LEAN := deg_to_rad(68.0) # a real crouch: the torso goes near-horizontal over the hips
const CROUCH_TORSO_SCALE := 0.85 # the crouched head (0.78 m) leaves less room than the torso is tall
const SPRINT_LEAN := deg_to_rad(16.0)
const WALK_LEAN := deg_to_rad(6.0)
const DIVE_PITCH := deg_to_rad(-80.0) # feet swing back behind the body
const WALL_ROLL := deg_to_rad(22.0) # top away from the wall, feet toward it
const THROW_PITCH := deg_to_rad(-14.0) # the knife throw leans over the front foot (#25)
const THROW_TWIST := deg_to_rad(-16.0) # and turns the shoulders with the throwing hand
const HIP_HALF_W := 0.09
const HIP_Y := 0.80 # standing hips: the legs have to be long enough to read as legs (#164)
const HIP_CROUCH_Y := 0.40 # folded: hips down, knees forward, feet planted
const KNEE_FWD := 0.02 # standing: knees almost straight
const KNEE_CROUCH_FWD := 0.20 # crouched: knees push forward
const KNEE_CROUCH_OUT := 0.05
const SHOULDER_LOCAL := Vector3(0.31, 0.27, 0.0) # the shoulder shard, in torso space
const RELOAD_TILT := deg_to_rad(26.0) # the mag dip, timed on the weapon's reload_time (#164)
const RELOAD_DROP := 0.06 # m, the torso settles while reloading
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
	# A crouch folds the figure (#164): hips drop, knees push forward, feet stay planted. The torso then
	# tucks under the head and keeps a mild compression so it does not poke out above a head that came
	# down 0.74 m.
	var pelvis_y := lerpf(HIP_Y, HIP_CROUCH_Y, k * (1.0 - dive))
	var reload := clampf(float(p.get("reload", 0.0)), 0.0, 1.0)
	var fold := k * (1.0 - dive)
	var torso_basis := Basis(Vector3.RIGHT, -lean + RELOAD_TILT * reload * 0.5) \
			* Basis.from_scale(Vector3(1, lerpf(1.0, 0.95, fold), 1))
	var up := torso_basis * Vector3.UP
	# Whole-figure turn around the neck: dive pitch, wall-run roll, and the landing roll's forward flip
	# (#205 - a rolling player used to stand upright in every view but their own camera).
	var flip := float(p.get("flip", 0.0))
	# The knife throw (#25): the torso turns away from the throwing side and pitches over the front foot.
	var thr := clampf(float(p.get("throw", 0.0)), 0.0, 1.0)
	var rig := Basis(Vector3.BACK, WALL_ROLL * wall) \
			* Basis(Vector3.RIGHT, DIVE_PITCH * dive + flip + THROW_PITCH * thr) \
			* Basis(Vector3.UP, THROW_TWIST * thr)

	# The torso and the hip joint travel along the *rotated* spine (`rig`), exactly like the seams and the
	# head. The torso used to be a vertical-only offset, so a dive or a roll pitched the figure while the
	# torso hung straight down - "de torso draait niet mee" (#243 review). The crouch only shortens the
	# hang, and the clamp that keeps it above the hips applies to the crouch alone, never to a dive.
	var hang := lerpf(TORSO_HANG, TORSO_HANG * 0.62, fold)
	var torso_pos: Vector3 = neck + rig * (-up * hang) + Vector3(0.0, bob - RELOAD_DROP * reload, 0.0)
	if fold > 0.0:
		torso_pos.y = maxf(torso_pos.y, pelvis_y + 0.10)
	# The hip joint sits on the crouch height (pelvis_y), not on a fixed hang: that is what lets the legs
	# stay long and still fold. Rotated with the rig so a dive keeps them attached.
	# Drop along world up (not the spine's up): the hips sit at the crouch height regardless of the lean,
	# and `rig` still carries them through a dive or a roll.
	var hip_pos: Vector3 = neck + rig * Vector3(0.0, pelvis_y - neck.y, 0.0)

	var out := {}
	var torso_tf := Transform3D(rig * torso_basis, torso_pos)
	out["torso"] = torso_tf
	out["neck_seam"] = Transform3D(rig * torso_basis, neck + rig * (up * 0.02))
	out["waist_seam"] = Transform3D(rig * torso_basis, (torso_pos + hip_pos) * 0.5)
	out["pelvis"] = Transform3D(rig * torso_basis, hip_pos)
	out["hips_y"] = pelvis_y
	out["head"] = Transform3D(rig * Basis(Vector3.RIGHT, -lean * 0.3), neck + rig * Vector3(0, NECK_DROP, 0))

	# Legs: hip -> knee -> foot, bending with the crouch. Detached like the rest of the figure, so the
	# shin and thigh read as crystal segments rather than a mesh skin.
	var feet: Array[Transform3D] = []
	var legs: Array[Transform3D] = []
	var hips: Array[Vector3] = []
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
		var f_unrot := f
		hips.append(hip_pos + rig * Vector3(side * HIP_HALF_W, 0.0, 0.0))
		f = neck + rig * (f - neck)
		var tilt := Basis(Vector3.RIGHT, -PI / 2) # foot mesh axis +Y → forward
		var toe := Basis(Vector3.RIGHT, (0.5 * sin(a) * lift / maxf(LIFT_WALK, 0.01)))
		feet.append(Transform3D(rig * toe * tilt, f))
		# Knee between hip and foot, pushed forward (and slightly out) with the crouch.
		var hip: Vector3 = hips[i]
		var knee := hip.lerp(f, 0.52)
		knee.z += -KNEE_FWD - KNEE_CROUCH_FWD * k * (1.0 - dive)
		knee.x += side * KNEE_CROUCH_OUT * k
		knee.y += 0.02 * (1.0 - f_unrot.y) # keep the knee above the straight line when the foot lifts
		legs.append(_segment(hip, knee))
		legs.append(_segment(knee, f))
	out["feet"] = feet
	out["legs"] = legs

	# Arms: from the shoulder shard to the hand on the gun, so the figure holds the weapon instead of
	# floating two blocks beside the torso (#164). Hand positions come from CrystalHands, in body space.
	var arms: Array[Transform3D] = []
	var hands: Array = p.get("hands", [])
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder: Vector3 = torso_tf * Vector3(SHOULDER_LOCAL.x * side, SHOULDER_LOCAL.y, SHOULDER_LOCAL.z)
		var hand: Vector3 = hands[i] if hands.size() > i else torso_tf * Vector3(side * 0.22, -0.02, -0.26)
		arms.append(_segment(shoulder, hand))
	out["arms"] = arms
	return out


## A limb segment: base at `a`, +Y along a->b, Y scaled to the length (CrystalMesh builds unit limbs).
static func _segment(a: Vector3, b: Vector3) -> Transform3D:
	var d := b - a
	# 2 cm longer than the gap: the two segments overlap at the joint instead of leaving a hole there.
	var l := maxf(d.length(), 0.02) + 0.02
	var y := d / l if d.length_squared() > 1e-8 else Vector3.UP
	var ref := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y * l, z), a)
