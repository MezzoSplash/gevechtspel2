class_name BotTricks
extends RefCounted
## A bot's movement tricks (#317 slice 1, from scripts/bot_brain.gd): the slide into a fight, the dive at a
## target below and the wall trick (jump at a wall BotWall found, run it, jump off). Static on the brain
## like Movement on the pawn: BotBrain keeps the state (_trick, _trick_t, _trick_cd, _trick_plan,
## _crouch_hold, ...) and its old function names as wrappers. The wallrun itself is Movement's, the same
## code a human runs.


## Slide into a fight, wallrun along a wall, dive at a target below. All three go through Movement, so a
## bot obeys exactly the same ranges, cooldowns and physics as the player.
static func tick(b: BotBrain, delta: float) -> void:
	b._crouch_hold = maxf(b._crouch_hold - delta, 0.0)
	var on_floor := b.pawn.is_on_floor()
	var foe := b._target
	var has_foe := foe != null and is_instance_valid(foe) and not foe.is_dead
	b._tick_wall_trick(delta, on_floor, has_foe)
	var tricking := b._trick != BotBrain.Trick.NONE # a dive or slide key would end the wallrun (crouch drops it)
	# A slide to close the last stretch of a fight, on the floor, moving fast, off cooldown.
	if tricking:
		pass
	elif on_floor and has_foe and b.state == BotBrain.State.FIGHT and not b.pawn._sliding and b._crouch_hold <= 0.0 and b.pawn._slide_cd <= 0.0:
		var dist := b.pawn.global_position.distance_to(foe.global_position)
		var fast := Vector2(b.pawn.velocity.x, b.pawn.velocity.z).length() >= Player.WALK_SPEED * 1.05
		if fast and dist > b.style.slide_min_m and dist < b.style.slide_max_m:
			b._crouch_press = true
			b._crouch_hold = BotBrain.BOT_SLIDE_HOLD
	# A dive when it is falling toward a target: closes the gap, and it lands into a roll.
	elif not on_floor and has_foe and b.pawn._dive_cd <= 0.0 and b.pawn.velocity.y < -1.0:
		if b.pawn.global_position.distance_to(foe.global_position) < BotBrain.BOT_DIVE_RANGE:
			b._crouch_press = true
			b._crouch_hold = maxf(b._crouch_hold, 0.2)
	b._set_bot_input()
	Movement.try_start_slide(b.pawn, on_floor, false)
	Movement.try_air_dive(b.pawn, on_floor, false)
	# #371: the crouch hold is for a trick that is actually running. A press that never became a slide or a
	# dive (the speed just under the threshold, a slide on cooldown, a foe that moved out of range) used to
	# keep the bot crouched for BOT_SLIDE_HOLD, and the fight slide then fired again the moment it ran out:
	# measured as 13% (Quay) to 34% (Townhouses) of the time crouched without sliding. While a slide runs the
	# key is held, because finish_slide ends a slide on release.
	if not b.pawn._sliding and not b.pawn._diving and b.pawn._roll_t <= 0.0:
		b._crouch_hold = 0.0
	# Forward is the travel direction (the brain faces it), so "forward held" is what walls want.
	Movement.tick_wallrun(b.pawn, delta, Vector2(0.0, -1.0), false)
	if b.pawn._wallrunning:
		var horiz := Vector3(b.pawn.velocity.x, 0.0, b.pawn.velocity.z)
		var along := horiz.normalized() if horiz.length_squared() > 0.01 else -b.pawn.transform.basis.z
		var h := Movement.wallrun_horiz(b.pawn, horiz, along, delta)
		b.pawn.velocity.x = h.x
		b.pawn.velocity.z = h.z
		# The wall replaces gravity, as in Player._physics_process: undo this tick's gravity, then sink slowly.
		# Without it a bot "wallran" at full gravity and dropped off the face in about half a second.
		var sink := lerpf(Player.WALLRUN_SINK_START, Player.WALLRUN_SINK_END, clampf(b.pawn._wallrun_t / Player.WALLRUN_TIME, 0.0, 1.0))
		var vy := b.pawn.velocity.y - float(b.pawn.get_gravity().y) * delta
		b.pawn.velocity.y = move_toward(vy, -sink, Player.WALLRUN_RISE_DAMP * delta) if vy > -sink else -sink
	if b.pawn._sliding:
		# Keep the slide on its own line at sprint speed; finish_slide decides when it is over.
		var dir := b.pawn._slide_dir
		var sp := maxf(Vector2(b.pawn.velocity.x, b.pawn.velocity.z).length(), Player.SPRINT_SPEED)
		b.pawn.velocity.x = dir.x * sp
		b.pawn.velocity.z = dir.z * sp
	Movement.finish_slide(b.pawn)
	# The same stance code the human runs: crouch follows the held key, and releases when the slide,
	# the dive or the roll is over.
	b.pawn._update_stance(delta, on_floor)


## Wall trick, one step per tick. Runs before the slide/dive keys and Movement.tick_wallrun, which do the
## actual wallrun (the same code a human runs); this only decides to jump at a wall, and when to jump off.
static func tick_wall_trick(b: BotBrain, delta: float, on_floor: bool, has_foe: bool) -> void:
	b._trick_cd = maxf(b._trick_cd - delta, 0.0)
	b._trick_scan_t = maxf(b._trick_scan_t - delta, 0.0)
	match b._trick:
		BotBrain.Trick.NONE:
			# #270: a wallrun route is exactly BotWall.MIN_LEN of face from its start, so the one scan
			# every TRICK_SCAN mostly came too late (or before the bot had turned along it) and the
			# cooldown of the last trick blocked the rest: tools/probe_bot_route measured one wallrun
			# in fifteen routes taken. On the route the run is the plan, so it looks every tick.
			if on_floor and b._on_wall_route():
				b._try_start_wall_trick()
			elif on_floor and b._trick_cd <= 0.0 and b._trick_scan_t <= 0.0:
				b._trick_scan_t = BotBrain.TRICK_SCAN
				b._try_start_wall_trick()
		BotBrain.Trick.AIR:
			b._trick_t += delta
			if b.pawn._wallrunning:
				b._trick = BotBrain.Trick.RUN
				b._trick_t = 0.0
			elif b.pawn.is_dead or (on_floor and b._trick_t > 0.15) or b._trick_t > BotBrain.TRICK_AIR_MAX:
				b._end_wall_trick() # missed the wall: land and carry on
			else:
				b._aim_into_wall() # the generic air steering would bend us back toward the path
		BotBrain.Trick.RUN:
			b._trick_t += delta
			if b.pawn.is_dead or not b.pawn._wallrunning:
				b._end_wall_trick()
			elif b._trick_t >= BotBrain.TRICK_JUMP_AT or (has_foe and b._can_see(b._target, true)):
				# Off the wall, away and up; only when there is floor to land on (a roof edge is a fall death).
				var n: Vector3 = b._trick_plan.n
				var along := Vector3(b.pawn.velocity.x, 0.0, b.pawn.velocity.z)
				var land := b.pawn.global_position + n * 4.5 + along.normalized() * 6.0
				if BotWall.floor_below(b.pawn.get_world_3d().direct_space_state, land, [b.pawn.get_rid()]):
					Movement.wall_jump(b.pawn)
					b._end_wall_trick()
				elif b._trick_t >= Player.WALLRUN_TIME:
					b._end_wall_trick() # no safe jump: ride it out, the run ends on its own


## On the floor and sprinting along the path: a wall alongside the heading, and the dice, start a trick.
static func try_start_wall_trick(b: BotBrain) -> void:
	# A held crouch (the tail of a slide) would drop the wallrun the moment it starts.
	if b.state == BotBrain.State.FIGHT or b._unstick_left > 0.0 or b.pawn._sliding or b.pawn._diving or b.pawn._roll_t > 0.0 or b.pawn.is_dead:
		return
	if b._crouch_hold > 0.0 or b._crouch_press:
		return
	var chance := float(Game.bot_profile().trick)
	if chance <= 0.0:
		return
	var heading := Vector3(b.pawn.velocity.x, 0.0, b.pawn.velocity.z)
	if heading.length() < BotBrain.TRICK_MIN_SPEED:
		return
	var space := b.pawn.get_world_3d().direct_space_state
	var plan := BotWall.find(space, b.pawn.global_position, heading, [b.pawn.get_rid()])
	if plan.is_empty():
		return
	# On a wallrun route the run is the plan, so no dice: the profile's chance only decides whether this
	# difficulty wallruns at all (Easy is 0 and returned above).
	if not b._on_wall_route() and b.rng.randf() >= chance:
		b._trick_cd = BotBrain.TRICK_SKIP_CD # this bot's own roll series, seeded per slot (#289) # said no to this wall: do not roll again at the next scan
		return
	b._trick_plan = plan
	b._trick = BotBrain.Trick.AIR
	b._trick_t = 0.0
	var speed := maxf(heading.length(), BotBrain.TRICK_MIN_SPEED)
	var dir := BotWall.entry_dir(plan)
	b.pawn.velocity = Vector3(dir.x * speed, Player.JUMP_SPEED, dir.z * speed)


## Keeps the horizontal velocity on the entry line (toward the wall) while the bot is in the air.
static func aim_into_wall(b: BotBrain) -> void:
	var dir := BotWall.entry_dir(b._trick_plan)
	var speed := maxf(Vector2(b.pawn.velocity.x, b.pawn.velocity.z).length(), BotBrain.TRICK_MIN_SPEED)
	b.pawn.velocity.x = dir.x * speed
	b.pawn.velocity.z = dir.z * speed


static func end_wall_trick(b: BotBrain) -> void:
	b._trick = BotBrain.Trick.NONE
	b._trick_t = 0.0
	b._trick_cd = BotBrain.TRICK_CD
	b._trick_plan = {}
