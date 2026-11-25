class_name BotFlank
extends RefCounted
## The flanker's patience (#382, #317 slice 5, from scripts/bot_brain.gd): when a flanking bot may open
## fire, and the ring point it approaches the enemy from. Static on the brain; the state (_flank_wait,
## _flank_lost, _flank_angle) stays on BotBrain and this is called with the brain as `b`.


## Sight bookkeeping. #382: the patience only restarts after a real loss of sight. It used to restart on
## every single tick without sight, so a bot that kept dipping in and out of view (a corner, a crate, or
## a player who keeps turning to face it) never reached flank_patience and circled instead of firing.
static func tick_sight(b: BotBrain, seen: bool, delta: float) -> void:
	if seen:
		b._flank_lost = 0.0
		b._flank_wait += delta
		return
	b._flank_lost += delta
	if b._flank_lost > BotBrain.FLANK_SIGHT_GRACE:
		b._flank_wait = 0.0
		return
	# A short dip (a crate, a corner, the target turning) does not stop the clock: it used to throw the
	# whole patience away, which is why a flanker against a player who keeps facing it never fired.
	b._flank_wait += delta


## Does this character get to open fire on `enemy` from where it stands? Only the flanker asks
## (#267 slice 2): no attack from straight ahead, a free shot from the side or the back, and a
## patience timer so it never circles forever in front of someone who keeps facing it.
static func aim_ok(b: BotBrain, enemy: Player, delta: float) -> bool:
	var to := b.pawn.global_position - enemy.global_position
	to.y = 0.0
	var facing := -enemy.transform.basis.z # the enemy's forward, flat
	facing.y = 0.0
	var from_side := true
	if facing.length_squared() > 0.0001 and to.length_squared() > 0.0001:
		# 1.0 is straight into the enemy's face, 0.0 is exactly the side.
		from_side = facing.normalized().dot(to.normalized()) < 0.35
	if from_side or b.pawn.global_position.distance_to(enemy.global_position) < BotBrain.FLANK_POINT_BLANK:
		b._flank_wait = 0.0
		return true
	# The clock runs in tick_sight, so a flickering target cannot stretch the wait forever.
	return b._flank_wait >= b.style.flank_patience


## Point on a ring around the enemy at fight range. Y stays theirs so roofs still route up a ramp.
static func point(b: BotBrain, center: Vector3) -> Vector3:
	var dest := center
	dest.x += cos(b._flank_angle) * BotAim.fight_range(b)
	dest.z += sin(b._flank_angle) * BotAim.fight_range(b)
	return dest
