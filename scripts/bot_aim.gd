class_name BotAim
extends RefCounted
## A bot's gun (#317 slice 4, from scripts/bot_brain.gd): the fight (strafe, hold range, bash, frag,
## shoot), the shank chase, the aim wobble and facing, and the per-gun numbers. Static on the brain like
## bot_cover; the state (_aim_*, _burst_*, _strafe_*, _seen_*) stays on BotBrain and this is called with
## the brain as `b`.
##
## The rng calls (randf for the wobble, randi_range/randf_range for a burst) stay in the same place in the
## tick, so the seeded replay does not move.


## The held gun, or null before a bot has one. Every per-gun number comes from here.
static func def(b: BotBrain) -> WeaponDef:
	return b.pawn.weapon.def if b.pawn and b.pawn.weapon else null


## The held gun decides the fight distance (WeaponDef.bot_fight_range). Sniper holds range, the
## shotgun closes in, the LMG holds a lane — all of that now lives in the .tres.
static func fight_range(b: BotBrain) -> float:
	var d := def(b)
	return d.bot_fight_range if d != null else BotBrain.NO_GUN_FIGHT


## The fight: aim, strafe, keep the gun's distance, bash close, frag at range, shoot when in range.
static func fight(b: BotBrain, enemy: Player, delta: float) -> void:
	if def(b) != null and def(b).melee:
		fight_shank(b, enemy, delta)
		return
	tick_aim_wobble(b, enemy, delta)
	face(b, enemy)
	var away := b.pawn.global_position - enemy.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = b.pawn.transform.basis.z
		away.y = 0.0
	away = away.normalized()
	var side := Vector3.UP.cross(away)
	side.y = 0.0
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	# Grinding a wall ends the commit so the probe can pick the open side.
	if b._stuck_pulse:
		b._strafe_hold = 0.0
		b._strafe_pause = 0.0
	if b._strafe_hold <= 0.0 and b._strafe_pause <= 0.0:
		BotNav.pick_strafe_side(b, side)
	var dist := b.pawn.global_position.distance_to(enemy.global_position)
	# One round left and they are already on top of us: close and bash. Spending it starts a reload.
	if b._hold_last_round(dist):
		if dist > BotBrain.MELEE_R:
			b._steer_to(b.pawn.global_position - away * 4.0, Player.SPRINT_SPEED, delta, false)
		if b._acquire_left <= 0.0 and dist <= BotBrain.MELEE_R:
			Game.melee.swing(b.pawn)
		return
	# This character's preferred distance, but never outside the range it is willing to shoot from.
	var fight_r := minf(fight_range(b) * b.style.range_scale, fight_range(b) + BotStyle.CLOSE_ENOUGH_M)
	var wish := Vector3.ZERO
	if b._strafe_pause > 0.0:
		b._strafe_pause = maxf(b._strafe_pause - delta, 0.0)
		# Almost still: only a step when the range is wrong, so the player gets a shot.
		if dist < b.style.back_off_m:
			wish = away
		elif dist > fight_r + b.style.hold_band:
			wish = -away
		if wish.length_squared() > 0.0001 and not b._side_open(wish, BotBrain.STRAFE_KEEP):
			wish = Vector3.ZERO
	else:
		# The commit is long enough to walk off a roof. Cut it when the next step closes.
		var strafe_dir := side * b._strafe_sign
		if not b._side_open(strafe_dir, BotBrain.STRAFE_KEEP):
			b._strafe_hold = 0.0
		else:
			b._strafe_hold = maxf(b._strafe_hold - delta, 0.0)
			wish = strafe_dir
			if dist < b.style.back_off_m:
				wish += away * 0.7
			elif dist > fight_r + b.style.hold_band:
				wish += -away * 0.7
			if wish.length_squared() > 1.0:
				wish = wish.normalized()
		if b._strafe_hold <= 0.0:
			# Next commit tries the other side. The probe still rejects a wall.
			b._strafe_sign *= -1.0
			b._strafe_pause = randf_range(BotBrain.STRAFE_PAUSE_MIN, BotBrain.STRAFE_PAUSE_MAX)
	# Fight steering is the wish itself. A nav path for this point is what made them hobble.
	b._steer_to(b.pawn.global_position + wish, BotBrain.STRAFE_SPEED, delta, false)
	if b._acquire_left <= 0.0 and dist <= BotBrain.MELEE_R and Game.melee.swing(b.pawn):
		return
	if b._acquire_left <= 0.0 and b._try_grenade(enemy, dist, delta):
		return
	if b._acquire_left <= 0.0 and dist <= fight_r + 4.0:
		try_shoot(b, enemy)


## Shank: close the last metres and stab. No strafe-shoot. The lunge is inside swing_shank.
static func fight_shank(b: BotBrain, enemy: Player, delta: float) -> void:
	tick_aim_wobble(b, enemy, delta)
	face(b, enemy)
	var dist := b.pawn.global_position.distance_to(enemy.global_position)
	var away := b.pawn.global_position - enemy.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = b.pawn.transform.basis.z
		away.y = 0.0
	else:
		away = away.normalized()
	if dist > Melee.SHANK_CHASE:
		b._steer_to(enemy.global_position, Player.SPRINT_SPEED, delta, true)
	else:
		b._steer_to(b.pawn.global_position - away * 4.0, Player.SPRINT_SPEED, delta, false)
	if b._acquire_left <= 0.0 and dist <= Melee.SHANK_RANGE + 0.8:
		Game.melee.swing_shank(b.pawn)


## Turn toward _aim_track (see tick_aim_wobble). Call tick_aim_wobble first in the same tick.
static func face(b: BotBrain, _enemy: Player) -> void:
	var look := b._aim_track
	look.y = b.pawn.global_position.y
	if look.distance_squared_to(b.pawn.global_position) > 0.04:
		b.pawn.look_at(look, Vector3.UP)
		b.pawn._yaw = b.pawn.rotation.y
	var aim := b._aim_track - b.pawn.head.global_position
	if aim.length_squared() < 0.0001:
		return
	aim = aim.normalized()
	# Positive pitch looks up (same as the mouse). This was negated, so bots aimed mirrored:
	# above anyone lower than their eyes, which is everyone, and crouchers most of all.
	b.pawn._pitch = clampf(asin(clampf(aim.y, -1.0, 1.0)), -Player.MAX_PITCH, Player.MAX_PITCH)
	b.pawn.head.rotation.x = b.pawn._pitch


## Body follows the path. Pitch stays level; the gun comes up only once they are in the fight.
static func face_travel(b: BotBrain, dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		return
	b.pawn.look_at(b.pawn.global_position + dir, Vector3.UP)
	b.pawn._yaw = b.pawn.rotation.y
	b.pawn._pitch = 0.0
	b.pawn.head.rotation.x = 0.0


## New random offset every AIM_WOBBLE_REPICK s, eased in so the crosshair drifts like a hand.
## The offset lies in the plane facing the bot (sideways and up/down), in metres at the target.
static func tick_aim_wobble(b: BotBrain, enemy: Player, delta: float) -> void:
	var fresh: bool = b._aim_for != enemy
	if fresh:
		b._aim_for = enemy
		b._aim_err_t = 0.0
	b._aim_err_t -= delta
	if b._aim_err_t <= 0.0:
		b._aim_err_t = BotBrain.AIM_WOBBLE_REPICK
		var dist := b.pawn.global_position.distance_to(enemy.global_position)
		var r := (BotBrain.AIM_WOBBLE_BASE + BotBrain.AIM_WOBBLE_PER_M * dist + BotBrain.AIM_WOBBLE_PER_SPEED * enemy._obs_speed) * float(Game.bot_profile().wobble)
		var bd := def(b)
		if bd != null:
			r *= bd.bot_aim_wobble_scale
		if fresh:
			r *= BotBrain.AIM_WOBBLE_FRESH
		var ang := randf() * TAU
		var mag := r * sqrt(randf())
		b._aim_err_goal = Vector2(cos(ang) * mag, sin(ang) * mag * 0.7)
		if fresh:
			b._aim_err = b._aim_err_goal
	b._aim_err = b._aim_err.lerp(b._aim_err_goal, 1.0 - exp(-8.0 * delta))
	var base := b._seen_point if b._seen_target == enemy else enemy.aim_point()
	var right := (base - b.pawn.head.global_position).cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	# Aim where the target really is (crouch lowers it), not at a fixed standing height.
	# The crosshair follows the target a beat late: a fast strafe is harder to hit than standing still.
	var goal := base + right * b._aim_err.x + Vector3.UP * b._aim_err.y
	var bd2 := def(b)
	var track := float(Game.bot_profile().track) * (bd2.bot_aim_track_scale if bd2 != null else 1.0)
	b._aim_track = goal if fresh else b._aim_track.lerp(goal, 1.0 - exp(-track * delta))


## One trigger pull at a time, in bursts the gun's .tres asks for.
static func try_shoot(b: BotBrain, enemy: Player) -> void:
	if b.pawn.weapon == null:
		return
	if b._burst_left <= 0:
		if b._burst_pause > 0.0:
			return
		b.pawn.weapon.burst_seq += 1 # a new trigger pull (SPRAY TRANSFER)
		var bd: WeaponDef = b.pawn.weapon.def
		if bd == null:
			return
		b._burst_left = randi_range(bd.bot_burst_min, bd.bot_burst_max)
		b._burst_pause = randf_range(bd.bot_burst_pause_min, bd.bot_burst_pause_max)
		b._burst_pause *= float(Game.bot_profile().pause)
	if b.pawn.weapon.bot_try_fire():
		b._burst_left -= 1
