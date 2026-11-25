class_name BotCover
extends RefCounted
## A Hard bot's reload out of sight (#269, #317 slice 1, from scripts/bot_brain.gd): whether to seek cover,
## holding the last round for a bash, the hide spot within COVER_R and the sprint to it. Static on the
## brain: BotBrain keeps _cover_live / _cover_point / _cover_flee and its old function names as wrappers.


## Hard reloads out of sight. Easy and Medium do not: the flag lives on the difficulty profile.
static func seeks_cover(b: BotBrain) -> bool:
	return bool(Game.bot_profile().get("cover", false))


## Empty or already reloading, and not close enough that a bash is the better use of the moment.
static func should_reload(b: BotBrain, enemy: Player) -> bool:
	if not b._seeks_cover() or b.pawn.weapon == null:
		return false
	var w := b.pawn.weapon
	# The shank has no mag (mag_size 0), so its ammo is always 0: without this a Hard shank bot was
	# "reloading" all the time - it ran to a hide spot and stabbed the air there instead of closing in.
	if w.def != null and w.def.melee:
		return false
	var dist := b.pawn.global_position.distance_to(enemy.global_position)
	if dist <= BotBrain.MELEE_R:
		return false
	if w.ammo == 1 and dist < BotBrain.RELOAD_HOLD_R:
		return false
	return w.is_reloading() or w.ammo <= 0


## The last round, inside RELOAD_HOLD_R. Shooting it is what would start the reload.
static func hold_last_round(b: BotBrain, dist: float) -> bool:
	if not b._seeks_cover() or b.pawn.weapon == null:
		return false
	if b.pawn.weapon.def != null and b.pawn.weapon.def.melee:
		return false # no rounds to hold: the shank stabs
	return b.pawn.weapon.ammo == 1 and dist < BotBrain.RELOAD_HOLD_R


## Sprint to the hide spot chosen when the reload started. No spot: back to the enemy, same sprint.
static func tick_reload(b: BotBrain, enemy: Player, delta: float) -> void:
	var w := b.pawn.weapon
	if w.ammo <= 0 and not w.is_reloading():
		w.bot_try_fire()
	if not b._cover_live:
		b._cover_live = true
		var spot := b._pick_cover(enemy)
		b._cover_flee = is_inf(spot.x)
		b._cover_point = spot
		if b.agent and not b._cover_flee:
			b.agent.target_position = spot
	var away := b.pawn.global_position - enemy.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -b.pawn.transform.basis.z
		away.y = 0.0
	away = away.normalized()
	if b._cover_flee:
		b._face_travel(away)
		b._steer_to(b.pawn.global_position + away * 6.0, Player.SPRINT_SPEED, delta, false)
		return
	b._face_travel(b._cover_point - b.pawn.global_position)
	b._steer_to(b._cover_point, Player.SPRINT_SPEED, delta, true)


## Nearest standable spot within COVER_R that the enemy's chest cannot see. The rays run once per
## reload, not per tick. A heading whose first step is a wall is skipped (`_side_open`). INF: flee.
static func pick(b: BotBrain, enemy: Player) -> Vector3:
	var space := b.pawn.get_world_3d().direct_space_state
	var origin := b.pawn.global_position
	var from := enemy.global_position + Vector3.UP * 0.9
	var best := Vector3(INF, INF, INF)
	var best_d := BotBrain.COVER_R + 0.01
	for i in BotBrain.COVER_SAMPLES:
		var ang := TAU * float(i) / float(BotBrain.COVER_SAMPLES)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		# The step in front of the feet has to be open. The crate itself can sit further along.
		if not b._side_open(dir, BotBrain.STRAFE_KEEP):
			continue
		for reach in BotBrain.COVER_REACHES:
			var spot := origin + dir * reach
			if not b._cover_floor(space, spot):
				continue
			var chest := spot + Vector3.UP * 0.9
			if from.distance_squared_to(chest) < 0.25:
				continue
			var q := PhysicsRayQueryParameters3D.create(from, chest)
			q.collision_mask = BotBrain.WORLD_MASK
			q.exclude = [b.pawn.get_rid(), enemy.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty() or not hit.has("position"):
				continue
			var hit_at := hit.position as Vector3
			if hit_at.distance_to(from) > from.distance_to(chest) - 0.35:
				continue
			var d := origin.distance_to(spot)
			if d < best_d:
				best_d = d
				best = spot
	return best


static func floor_ok(b: BotBrain, space: PhysicsDirectSpaceState3D, spot: Vector3) -> bool:
	var foot := spot + Vector3.UP * 0.4
	var q := PhysicsRayQueryParameters3D.create(foot, foot + Vector3.DOWN * BotBrain.STRAFE_FLOOR)
	q.collision_mask = BotBrain.WORLD_MASK
	var hit := space.intersect_ray(q)
	if not hit.has("normal"):
		return false
	var slope := rad_to_deg(acos(clampf((hit.normal as Vector3).dot(Vector3.UP), -1.0, 1.0)))
	return slope <= BotBrain.MAX_STEP_SLOPE + 4.0
