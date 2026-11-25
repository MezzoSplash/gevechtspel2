class_name BotSight
extends RefCounted
## What a bot can see (#272, #317 slice 6, from scripts/bot_brain.gd): the line-of-sight probe with its
## short-lived cache, and the two difficulty switches around it. Static on the brain; the cache (_los,
## los_ttl, los_cache) and the aim point it records (_seen_target, _seen_point) stay on BotBrain, and this
## is called with the brain as `b`.


static func omniscient(b: BotBrain) -> bool:
	return bool(Game.bot_profile().omni)


## Does this bot know where `e` is? Untyped like _valid_target: check validity first, the pawn may be freed.
static func knows(b: BotBrain, e) -> bool:
	return omniscient(b) or b._known.has(e.get_instance_id())


## World (1) + players (2). Teammates are see-through (shots pass them too); other enemies still block.
## Body centre first, then the head (peeking over cover). The point that is clear becomes the aim point.
##
## #272: the answer is cached for `los_ttl` physics ticks. `_pick_target()` probes every enemy it meets
## and then `_fight()`/`_hunt()` ask again for the one they got, and the `fighting` test asks every tick
## for the same pawn. `los_cache = false` is the old per-call behaviour, so the same build can be measured
## both ways.
static func can_see(b: BotBrain, enemy: Player, fresh: bool = false) -> bool:
	if b.los_cache and not fresh:
		var frame := Engine.get_physics_frames()
		var known: Dictionary = b._los.get(enemy.get_instance_id(), {})
		if not known.is_empty() and frame - int(known["frame"]) < b.los_ttl:
			var vis: bool = known["vis"]
			if vis:
				b._seen_target = enemy
				b._seen_point = known["point"] as Vector3
			return vis
	var from := b.pawn.head.global_position
	var space := b.pawn.get_world_3d().direct_space_state
	var seen := false
	var at := Vector3.ZERO
	for to in [enemy.aim_point(), enemy.head_point()]:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = BotBrain.SHOT_MASK
		query.exclude = Game.shot_exclude(b.pawn)
		if BotBrain.count_rays:
			BotBrain.los_rays += 1
		var hit := space.intersect_ray(query)
		if hit.has("collider") and hit.collider == enemy:
			seen = true
			at = to
			break
	if seen:
		b._seen_target = enemy
		b._seen_point = at
		b._remember(enemy, enemy.global_position)
	if b.los_cache:
		if b._los.size() > BotBrain.LOS_CACHE_MAX:
			b._los.clear() # freed pawns leave entries behind; nothing here is worth an unbounded map
		b._los[enemy.get_instance_id()] = {
			"vis": seen, "point": at, "frame": Engine.get_physics_frames(),
		}
	return seen
