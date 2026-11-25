class_name BotTarget
extends RefCounted
## Who a bot goes after (#317 slice 7, from scripts/bot_brain.gd): the target pick with its retarget beat,
## the validity rule for a pawn, and the "someone shot me" threat. Static on the brain; the state
## (_target, _threat, _retarget_t, _hurt_retreat_left, ...) stays on BotBrain and this takes `b`.


## The enemy this tick works on, or null for a patrol. A still-valid target is kept for RETARGET s unless
## the pawn who shot us is in sight, and the pick prefers the threat over whoever is nearest.
static func pick(b: BotBrain, delta: float) -> Player:
	b._retarget_t -= delta
	if b._retarget_t > 0.0 and valid(b, b._target) and b._knows(b._target):
		# Still look now when the pawn who shot us is in sight and not the current target.
		if not (valid(b, b._threat) and b._target != b._threat and b._can_see(b._threat)):
			return b._target
	b._retarget_t = BotBrain.RETARGET
	var enemies := b._enemies_by_distance()
	b._listen(enemies)
	var prev := b._target
	b._target = null
	# #150: the shooter, if we can see them, even when someone else is closer.
	if valid(b, b._threat) and b._can_see(b._threat):
		b._target = b._threat
	else:
		for e in enemies:
			if b._can_see(e):
				b._target = e
				break
	if b._target == null and valid(b, b._threat) and b._knows(b._threat):
		b._target = b._threat # hunt the one who shot, not whoever is nearest through a wall
	elif b._target == null:
		b._target = b._nearest_known(enemies) # null when nobody is known: the bot patrols
	if b._target != prev:
		b._reset_hunt()
	return b._target


## Untyped on purpose: a freed pawn in a typed Player argument is a runtime error.
static func valid(b: BotBrain, p) -> bool:
	return (
		is_instance_valid(p)
		and not p.is_queued_for_deletion()
		and not p.is_dead
		and (p.team_id != b.pawn.team_id or Game.is_ffa())
		and p != b.pawn
	)


## #150: a hit from another pawn. Prefer them as the target, and break off the trade when low.
static func note_threat(b: BotBrain, attacker: Player) -> void:
	if not valid(b, attacker):
		return
	b._threat = attacker
	b._threat_left = BotBrain.THREAT_TIME
	b._retarget_t = 0.0
	b._remember(attacker, attacker.global_position) # being hit tells you where it came from
	if b.style.retreat_hp > 0.0 and Game.hp_of(b.pawn) <= b.style.retreat_hp and b._retreat_cd <= 0.0:
		b._hurt_retreat_left = BotBrain.RETREAT_TIME
		b._retreat_cd = BotBrain.RETREAT_CD
		b._set_state(BotBrain.State.RETREAT)
		# The flipped flank is what brings them back in from the other side.
		b._route = BotBrain.Route.FLANK
		b._flank_angle += PI
		b._flank_flipped = true
		b._drop_path()
