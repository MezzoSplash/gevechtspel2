class_name BotGrenade
extends RefCounted
## A bot's frag throw (#317 slice 1, from scripts/bot_brain.gd): when to throw, the pitch that lands it
## near the target before the fuse, and the arc check that refuses a throw into a ceiling (#271). Static on
## the brain: BotBrain keeps _nade_cd / _nade_check and its old function names as wrappers.


## Frag at a visible enemy in mid range. The pitch is solved so the arc lands near them before the fuse.
## A pitch whose arc hits the world (a ceiling, a lip, a door head) is refused, and the cooldown
## stays: the bot can try again on the next check instead of bouncing the frag into its own feet.
static func try_throw(b: BotBrain, enemy: Player, dist: float, delta: float) -> bool:
	b._nade_check -= delta
	if b._nade_cd > 0.0 or b.pawn.grenades <= 0 or b._nade_check > 0.0:
		return false
	b._nade_check = BotBrain.NADE_CHECK
	if dist < BotBrain.NADE_MIN or dist > BotBrain.NADE_MAX or randf() > b.style.nade_chance:
		return false
	var from := b.pawn.head.global_position
	var to := enemy.global_position + Vector3(0.0, 0.4, 0.0)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var d := flat.length()
	if d < 0.5:
		return false
	var pitches := b._grenade_pitches(from, to, d)
	if pitches.is_empty():
		return false
	if b._throw_pitched(from, flat, to, pitches[0]):
		return true
	# One higher arc. A low ceiling that eats the flat toss sometimes still has a lob over it.
	for i in range(1, pitches.size()):
		if pitches[i] > pitches[0]:
			return b._throw_pitched(from, flat, to, pitches[i])
	return false


## Pitches that land within 2 m of the target, best error first. The +4 m/s is Grenade.initial_velocity.
static func pitches(b: BotBrain, from: Vector3, to: Vector3, d: float) -> Array[float]:
	var dy := to.y - from.y
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var scored: Array[Vector2] = []
	for k in 25:
		var pitch := lerpf(-0.35, 0.9, float(k) / 24.0)
		var h := Grenade.THROW_SPEED * cos(pitch)
		if h < 0.5:
			continue
		var t := d / h
		if t > Grenade.FUSE + 0.15:
			continue
		var vy := Grenade.THROW_SPEED * sin(pitch) + 4.0
		var err := absf(vy * t - 0.5 * g * t * t - dy)
		if err <= 2.0:
			scored.append(Vector2(err, pitch))
	scored.sort()
	var out: Array[float] = []
	for s in scored:
		out.append(s.y)
	return out


## Throw `pitch` if the arc is clear. False leaves the cooldown alone.
static func throw_pitched(b: BotBrain, from: Vector3, flat: Vector3, to: Vector3, pitch: float) -> bool:
	var dir := flat.normalized() * cos(pitch) + Vector3.UP * sin(pitch)
	dir = (dir + Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04))).normalized()
	var origin := from + dir * 0.6
	if not b._grenade_arc_clear(origin, Grenade.initial_velocity(dir), to):
		return false
	b._nade_cd = randf_range(BotBrain.NADE_COOLDOWN_MIN, BotBrain.NADE_COOLDOWN_MAX) * float(Game.bot_profile().nade)
	Game.throw_grenade(b.pawn, origin, dir)
	return true


## Eight rays along origin + v*t + ½gt², out to the target. Grenade.MASK, so a wall, a lip or an
## RC-XD blocks it. Pawns are excluded: the arc is aimed at one, and the fuse is a timer.
static func arc_clear(b: BotBrain, origin: Vector3, vel: Vector3, target: Vector3) -> bool:
	var hv := Vector2(vel.x, vel.z)
	var to := Vector2(target.x - origin.x, target.z - origin.z)
	if hv.length() < 0.5 or to.length() < 0.05:
		return false
	var flight := clampf(to.length() / hv.length(), 0.05, Grenade.FUSE)
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var space := b.pawn.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for n in b.pawn.get_tree().get_nodes_in_group("player"):
		var body := n as CollisionObject3D
		if body:
			exclude.append(body.get_rid())
	var prev := origin
	for i in BotBrain.NADE_ARC_STEPS:
		var t := flight * float(i + 1) / float(BotBrain.NADE_ARC_STEPS)
		var at := origin + vel * t + Vector3(0.0, -0.5 * g * t * t, 0.0)
		var q := PhysicsRayQueryParameters3D.create(prev, at)
		q.collision_mask = Grenade.MASK
		q.exclude = exclude
		if not space.intersect_ray(q).is_empty():
			return false
		prev = at
	return true
