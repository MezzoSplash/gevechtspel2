class_name ReloadAnims
extends RefCounted
## #252: one reload per weapon style instead of one generic tilt for all eight guns. A style is a set of
## keyframed curves over the reload's own progress t (0..1, timed on the weapon's `reload_time`), and
## `solve()` samples them: what the gun does (rotation + offset), where the left hand goes, and how far
## the loose parts (magazine, top cover, bolt) are along their travel. Pure data — Weapon applies it to
## the viewmodel and the check samples it without a pawn. The third-person hand reads the same styles in
## the second half of #252.
##
## The minimum amplitudes are what the eye needs in a first-person view: under roughly 0.3 rad of gun
## rotation and 12 cm of left-hand travel a reload does not read at all (issue #252).

const MAG := &"mag"
const SHELLS := &"shells"
const CYLINDER := &"cylinder"
const BOLT := &"bolt"
## Every style a `.tres` may name. `check_reload_anim` refuses a gun whose `reload_style` is not here.
const STYLES: Array[StringName] = [MAG, SHELLS, CYLINDER, BOLT]

## Minimum gun rotation a style has to produce somewhere in the reload, in rad (#252: 0.3).
const MIN_ROT := 0.3
## Minimum travel of the left hand away from its rest pose, in metres (#252: 0.12).
const MIN_HAND := 0.12

## Rest pose of the left hand in weapon space: under the barrel, a little to the left of the gun.
const HAND_REST := Vector3(-0.07, -0.13, -0.14)
## The loose magazine: hanging under the well at `mag` 0, dropped at `mag` 1.
const MAG_WELL := Vector3(0.0, -0.14, -0.02)
const MAG_DROPPED := Vector3(0.03, -0.32, 0.06)
## Where the hand loads a shell (shotgun / slug), works the cylinder (revolver) and seats a clip (sniper).
const SHELL_PORT := Vector3(-0.02, -0.20, -0.02)
const CYLINDER_SIDE := Vector3(0.05, -0.14, -0.08)
const CLIP_POS := Vector3(0.0, -0.16, -0.04)
## The LMG's top cover: closed at `cover` 0, hinged up at `cover` 1.
const COVER_CLOSED := Vector3(0.0, 0.075, -0.02)
const COVER_OPEN := Vector3(0.0, 0.115, -0.03)


## Samples one reload. `shells` is how many rounds the tubes are missing (the insert loops),
## `cover_hinge` is the LMG's top cover on the `mag` style. Everything is clamped, so any t is safe.
static func solve(style: StringName, t: float, shells := 1, cover_hinge := false) -> Dictionary:
	var tt := clampf(t, 0.0, 1.0)
	match style:
		SHELLS:
			return _shells(tt, shells)
		CYLINDER:
			return _cylinder(tt)
		BOLT:
			return _bolt(tt)
	return _mag(tt, cover_hinge)


## Piecewise smoothstep through `keys` ([[t, value], ...] with t ascending). Outside the range the first
## and last value hold, so a curve never kinks at either end of a reload.
static func track(keys: Array, t: float) -> float:
	if keys.is_empty():
		return 0.0
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		var k0: Array = keys[i - 1]
		var k1: Array = keys[i]
		if t <= float(k1[0]):
			var span := float(k1[0]) - float(k0[0])
			var f := 0.0 if span <= 0.0 else (t - float(k0[0])) / span
			return lerpf(float(k0[1]), float(k1[1]), smoothstep(0.0, 1.0, f))
	return float(keys[keys.size() - 1][1])


## The left hand for this frame: where it is (`pos`) and how far it has left its hold on the gun (`w`,
## 0..1). CrystalHands blends its own foregrip target toward `pos` by `w`, so the hand travels from the
## gun to the mag instead of teleporting there.
static func reach(dest: Vector3, t: float, t_in: float, t_out: float, t_back: float) -> Dictionary:
	var w := track([[0.0, 0.0], [t_in, 1.0], [t_out, 1.0], [t_back, 0.0]], t)
	return {"pos": HAND_REST.lerp(dest, w), "w": w}


## One sampled pose. `rot` is added to the weapon's rotation (rad), `pos` to its position (m), `hand` is
## where the left hand belongs in weapon space with `hand_w` as its blend weight, and `mag` / `cover` /
## `bolt` are 0..1 travel for the loose parts.
static func _pose(rot: Vector3, pos: Vector3, hand: Dictionary, mag := 0.0, cover := 0.0, bolt := 0.0, loops := 0) -> Dictionary:
	return {"rot": rot, "pos": pos, "hand": hand.pos, "hand_w": hand.w, "mag": mag, "cover": cover, "bolt": bolt, "loops": loops}


## `mag` (rifle, smg, pistol, lmg): the gun tilts on its side so the well faces the hand and drops a
## little. The old magazine leaves, the hand pushes a fresh one home with a jolt at ~60%, and at ~85%
## the charging handle gets a short pull. A hinge (`cover_hinge`, the LMG) lifts the top cover at
## 18-74% instead of the empty well.
static func _mag(t: float, cover_hinge: bool) -> Dictionary:
	var roll := track([[0.0, 0.0], [0.16, -0.62], [0.70, -0.56], [0.90, 0.0]], t) # on its side
	var pitch := track([[0.0, 0.0], [0.20, -0.12], [0.80, -0.10], [0.96, 0.0]], t) # muzzle a touch down
	var dip := track([[0.0, 0.0], [0.14, -0.06], [0.72, -0.05], [0.94, 0.0]], t)
	var seat := track([[0.50, 0.0], [0.58, -0.022], [0.66, 0.0]], t) # the fresh mag seats
	var handle := track([[0.78, 0.0], [0.85, 0.05], [0.92, 0.0]], t) # charging handle
	var hand := reach(MAG_WELL + Vector3(-0.02, -0.02, 0.02), t, 0.30, 0.42, 0.80)
	var push := track([[0.54, 0.0], [0.61, 1.0], [0.70, 0.0]], t)
	hand.pos += Vector3(0.0, 0.02, -0.04) * push # the palm drives the mag in
	var mag := track([[0.0, 0.0], [0.44, 0.0], [0.54, 1.0], [0.60, 1.0], [0.66, 0.0]], t)
	var cover := 0.0
	if cover_hinge:
		cover = track([[0.0, 0.0], [0.18, 1.0], [0.55, 1.0], [0.74, 0.0]], t)
	return _pose(Vector3(pitch, 0.0, roll), Vector3(0.02, dip + seat, handle), hand, mag, cover)


## `shells` (shotgun, slug): the gun tilts outward and the hand loads one shell per missing round,
## each a dip-and-push, over the loading window. The reload ends with a pump. `shells` sets the loop
## count, so an almost empty tube takes visibly longer than one that lost two rounds.
static func _shells(t: float, shells: int) -> Dictionary:
	var n := maxi(shells, 1)
	var roll := track([[0.0, 0.0], [0.14, 0.46], [0.80, 0.42], [0.96, 0.0]], t) # outward, away from the port
	var pitch := track([[0.0, 0.0], [0.18, 0.16], [0.80, 0.14], [0.96, 0.0]], t)
	var pump := track([[0.82, 0.0], [0.87, 0.09], [0.92, 0.0], [0.96, 0.03], [1.0, 0.0]], t)
	var hand := reach(SHELL_PORT, t, 0.12, 0.80, 0.92)
	var w0 := 0.14 # the load window the loops are spread over
	var w1 := 0.80
	var frac := 0.0
	if t > w0 and t < w1:
		var local := (t - w0) / (w1 - w0) * float(n)
		frac = local - floor(local)
	hand.pos += Vector3(0.0, -0.07 * sin(frac * PI), -0.035 * maxf(0.0, sin((frac - 0.45) * PI)))
	return _pose(Vector3(pitch, 0.0, roll), Vector3(0.0, -0.03, pump), hand, 0.0, 0.0, 0.0, n)


## `cylinder` (revolver): the gun rolls far over to the left so the cylinder faces you, a flick up at
## the halfway point throws the spent cases out, the hand works the cylinder, and it swings back with a
## little spin that ends the reload.
static func _cylinder(t: float) -> Dictionary:
	var roll := track([[0.0, 0.0], [0.18, 1.22], [0.72, 1.22], [0.86, 0.0], [0.93, 0.10], [1.0, 0.0]], t)
	var pitch := track([[0.0, 0.0], [0.40, 0.0], [0.50, -0.34], [0.60, 0.0]], t) # the flick
	var yaw := track([[0.0, 0.0], [0.74, 0.0], [0.88, 0.24], [0.98, 0.0]], t) # the spin closing it
	var hand := reach(CYLINDER_SIDE, t, 0.34, 0.74, 0.88)
	return _pose(Vector3(pitch, yaw, roll), Vector3(0.0, -0.04, 0.0), hand)


## `bolt` (sniper): the gun comes up so the eye stays on the port while the bolt goes back and forward
## (the gun itself steps back 7 cm with it), then the hand seats a clip.
static func _bolt(t: float) -> Dictionary:
	var pitch := track([[0.0, 0.0], [0.12, -0.34], [0.86, -0.30], [0.96, 0.0]], t)
	var pull := track([[0.0, 0.0], [0.16, 0.0], [0.26, 1.0], [0.34, 1.0], [0.46, 0.0]], t)
	var hand := reach(CLIP_POS, t, 0.52, 0.78, 0.92)
	return _pose(Vector3(pitch, 0.0, 0.0), Vector3(0.0, 0.0, 0.07 * pull), hand, 0.0, 0.0, pull)
