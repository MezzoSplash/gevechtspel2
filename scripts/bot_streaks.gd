class_name BotStreaks
extends RefCounted
## A bot's scorestreaks (#317 slice 5, from scripts/bot_brain.gd): which charge to spend and how to
## drive the RC-XD. Static on the brain, like bot_cover / bot_grenade / bot_tricks / bot_wall: the brain
## keeps _streak_wait, _rc_repath and _rc_point and calls this with itself as `b`.

## Spends one banked streak when the profile's cooldown allows it: the UAV first (it needs nothing),
## then Overdrive (#388: allowed for bots, no target needed), then the RC-XD when the enemy is far or
## out of sight. The slot for each comes from the bot's own pick (#387), not a fixed index.
static func tick(b: BotBrain, delta: float, enemy: Player) -> void:
	var charges := int(Game.streak_charges.get(b.pawn.peer_id, 0))
	if charges == 0:
		b._streak_wait = float(Game.bot_profile().streak)
		return
	b._streak_wait = maxf(b._streak_wait - delta, 0.0)
	if b._streak_wait > 0.0:
		return
	if (charges & Game.CHARGE_RADAR) != 0:
		Game.try_activate_streak(b.pawn.peer_id, StreakSelect.slot_for(Game, b.pawn.peer_id, &"uav"))
		b._streak_wait = float(Game.bot_profile().streak)
		return
	if (charges & Game.CHARGE_OVERDRIVE) != 0 and Overdrive.for_owner(b.pawn.peer_id) == null:
		Game.try_activate_streak(b.pawn.peer_id, StreakSelect.slot_for(Game, b.pawn.peer_id, &"overdrive"))
		b._streak_wait = float(Game.bot_profile().streak)
		return
	if (charges & Game.CHARGE_RCXD) != 0 and enemy != null:
		var far := b.pawn.global_position.distance_to(b._goal_pos(enemy)) >= BotBrain.RC_LAUNCH_MIN
		if far or not b._can_see(enemy):
			Game.try_activate_streak(b.pawn.peer_id, StreakSelect.slot_for(Game, b.pawn.peer_id, &"rcxd"))
			b._rc_repath = 0.0
			b._streak_wait = float(Game.bot_profile().streak)


## While our car is out the pawn stands still (like a player in the RC view) and we steer the car
## along the navmesh to the nearest enemy, then blow it up next to them.
static func drive_rc(b: BotBrain, delta: float) -> bool:
	var car := RcXd.for_owner(b.pawn.peer_id)
	if car == null:
		return false
	b._set_state(BotBrain.State.RC)
	b.pawn.velocity.x = 0.0
	b.pawn.velocity.z = 0.0
	b.pawn.move_and_slide()
	var here := car.global_position
	var best: Player = null
	var best_d := INF
	for p in Game.players(): # #272
		if p == b.pawn or p.is_dead or not Game.is_enemy(p, b.pawn):
			continue
		var dd := here.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = p
	if best == null:
		car.apply_remote_input(car.yaw, 0.0)
		return true
	if best_d <= BotBrain.RC_BLOW_R:
		car.shutdown(true)
		return true
	b._rc_repath -= delta
	if b._rc_repath <= 0.0 or here.distance_to(b._rc_point) < 1.2:
		b._rc_repath = 0.4
		b._rc_point = best.global_position
		if b.agent:
			var path := NavigationServer3D.map_get_path(b.agent.get_navigation_map(), here, best.global_position, true)
			for pt in path:
				if Vector2(pt.x - here.x, pt.z - here.z).length() > 1.5:
					b._rc_point = pt
					break
	var to := b._rc_point - here
	var want_yaw := atan2(-to.x, -to.z) if Vector2(to.x, to.z).length() > 0.05 else car.yaw
	var turn := absf(wrapf(want_yaw - car.yaw, -PI, PI))
	car.apply_remote_input(want_yaw, 0.55 if turn > 1.2 else 1.0)
	return true
