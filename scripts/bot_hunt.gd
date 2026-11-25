class_name BotHunt
extends RefCounted
## A bot's chase (#317 slice 2, from scripts/bot_brain.gd): the authored-route hints, the flank/direct
## hunt and the stuck escalation. Static on the brain like bot_cover and friends: the state it reads and
## writes (_hint, _route, _path_*, _flank_*, _stuck_pulse) stays on BotBrain, and this is called with the
## brain as `b`.


## #270: look for an authored route worth taking right now. Cheap when the map ships none (one cached
## look-up that returns an empty list) and skipped entirely while a route is already being followed.
static func try_pick_hint(b: BotBrain, enemy: Player) -> void:
	var space := b.pawn.get_world_3d().direct_space_state
	var routes := BotRoutes.for_map(space, Game.map_id)
	if routes.is_empty():
		return
	var h := BotRoutes.pick(space, routes, b.pawn.global_position, b._goal_pos(enemy))
	if h.is_empty():
		return
	b._hint = h.duplicate(true)
	b._hint_i = 1
	b._hint_pos = b.pawn.global_position
	b._hint_t = 0.0
	b._hint_pressed = false


## Walk one authored route. The kind only decides the keys: a slide route presses crouch once at the
## start, a wallrun or surf route is run at sprint straight at the next point and the movement code
## (#278's wall trick, the surf state) takes over when the geometry offers it.
static func follow_hint(b: BotBrain, enemy: Player, delta: float) -> void:
	var pts: Array = b._hint.get("points", [])
	if b._hint_i >= pts.size():
		clear_hint(b)
		return
	var dest: Vector3 = pts[b._hint_i]
	if Vector2(dest.x - b.pawn.global_position.x, dest.z - b.pawn.global_position.z).length() < BotBrain.HINT_ARRIVE:
		b._hint_i += 1
		b._hint_pos = b.pawn.global_position
		b._hint_t = 0.0
		if b._hint_i >= pts.size():
			clear_hint(b) # the route delivered us: the hunt takes it from here
			return
		dest = pts[b._hint_i]
	# No progress: a route that does not move the bot is worse than no route at all.
	b._hint_t += delta
	if b.pawn.global_position.distance_to(b._hint_pos) > BotBrain.HINT_STALL_DIST:
		b._hint_pos = b.pawn.global_position
		b._hint_t = 0.0
	elif b._hint_t >= BotBrain.HINT_STALL:
		clear_hint(b)
		return
	# A slide needs speed to start: pressing crouch while walking just crouches the bot and it crawls
	# the rest of the route at a walk - measured in check_bot_route (11 m/s -> 1 m/s -> stall).
	var fast := Vector2(b.pawn.velocity.x, b.pawn.velocity.z).length() >= Player.SPRINT_SPEED * 0.9
	if (StringName(b._hint.get("kind", &"")) == &"slide"
			and fast and not b._hint_pressed and b.pawn.is_on_floor()
			and b._crouch_hold <= 0.0 and b._crouch_press == false and b.pawn._slide_cd <= 0.0):
		b._hint_pressed = true
		b._crouch_press = true
		b._crouch_hold = BotBrain.BOT_SLIDE_HOLD
	b._tick_aim_wobble(enemy, delta)
	b._face_travel(dest - b.pawn.global_position)
	b._steer_to(dest, Player.SPRINT_SPEED, delta, false)


static func on_wall_route(b: BotBrain) -> bool:
	return StringName(b._hint.get("kind", &"")) == &"wallrun"


static func clear_hint(b: BotBrain) -> void:
	b._hint = {}
	b._hint_i = 0
	b._hint_t = 0.0
	b._hint_pressed = false


## No line of sight, or seen but outside gun range. Follow the navmesh.
## First to a point beside the enemy (different bots, different doors), then to their feet.
static func hunt(b: BotBrain, enemy: Player, delta: float) -> void:
	if b._route == BotBrain.Route.DIRECT:
		direct(b, enemy, delta)
	else:
		flank(b, enemy, delta)


## Flank: aim for a point on the ring around the enemy, so two bots do not file through one door.
## A path that runs out means the ring point was useless, and the chase goes straight at them.
static func flank(b: BotBrain, enemy: Player, delta: float) -> void:
	b._set_state(BotBrain.State.HUNT_FLANK)
	begin(b)
	var at := b._goal_pos(enemy)
	# A ring point it has already reached is worth leaving (#267 slice 2): the flanker takes the next
	# angle on the enemy instead of standing on the spot, which is what "slaat vaker een hoek om" is.
	if (b.style.flank_switch_per_s > 0.0
			and b.pawn.global_position.distance_to(b._flank_point(at)) < BotBrain.FLANK_ARRIVE
			and b.rng.randf() < 1.0 - exp(-b.style.flank_switch_per_s * delta)):
		b._flank_angle += BotBrain.FLANK_TURN * (1.0 if b.rng.randf() < 0.5 else -1.0)
		b._flank_flipped = false # a new angle is a new chase, not an escalation
		b._drop_path()
	# is_navigation_finished is still true the frame a target is set; the path arrives after.
	var followed := b._path_live and b._repath_t < BotBrain.HUNT_REPATH - 0.2
	if followed and b.agent and b.agent.is_navigation_finished():
		b._route = BotBrain.Route.DIRECT
		b._set_state(BotBrain.State.HUNT_DIRECT)
		b._force_repath = true
	leg(b, enemy, delta, at if b._route == BotBrain.Route.DIRECT else b._flank_point(at), at)


## Direct: the enemy's feet, from wherever the flank left us.
static func direct(b: BotBrain, enemy: Player, delta: float) -> void:
	b._set_state(BotBrain.State.HUNT_DIRECT)
	begin(b)
	var at := b._goal_pos(enemy)
	leg(b, enemy, delta, at, at)


## Both halves start here: a target with no path yet asks the navmesh, a stuck hunt escalates.
static func begin(b: BotBrain) -> void:
	if not b._path_live:
		b._force_repath = true
	if b._stuck_pulse:
		on_stuck(b)


## One leg of the chase. `at` is where we think the enemy is: the path is remembered against it,
## so a target that moved further than HUNT_SHIFT makes us plan again instead of walking on.
static func leg(b: BotBrain, enemy: Player, delta: float, dest: Vector3, at: Vector3) -> void:
	var shifted := (
		b._path_live
		and b._path_enemy.distance_squared_to(at) > BotBrain.HUNT_SHIFT * BotBrain.HUNT_SHIFT
	)
	b._repath_t -= delta
	# Keep the enemy's height. Snapping to our own y picks the floor under a roof, so the
	# path never takes the ramp when someone is standing up there. Steering still ignores y.
	if b.agent and (b._repath_t <= 0.0 or shifted or b._force_repath):
		b.agent.target_position = dest
		b._path_enemy = at
		b._path_live = true
		b._repath_t = BotBrain.HUNT_REPATH
		b._force_repath = false
	var travel := dest - b.pawn.global_position
	if b.agent and not b.agent.is_navigation_finished():
		travel = b.agent.get_next_path_position() - b.pawn.global_position
	# Keep the aim warm, but look along the path. Facing the enemy here is the moonwalk.
	b._tick_aim_wobble(enemy, delta)
	b._face_travel(travel)
	# Closing the gap at a walk is what made a chase look like a stroll. Shots stay
	# in the fight, where the wish speed is the strafe, so sprint does not tighten aim.
	b._steer_to(dest, Player.SPRINT_SPEED, delta, true)
	# Reached the last known spot and nobody is in sight: they moved on. Forget them and look elsewhere.
	if not b._omniscient():
		var flat := Vector2(b.pawn.global_position.x - at.x, b.pawn.global_position.z - at.z).length()
		if flat < BotBrain.SEARCH_ARRIVE and not b._can_see(enemy):
			b._forget(enemy)


## A hunt that stopped making progress: straight at the target asks for an unstick, a flank takes the
## opposite angle once, and a flank that is already flipped commits to a direct chase.
static func on_stuck(b: BotBrain) -> void:
	if b._route == BotBrain.Route.DIRECT:
		BotNav.pick_unstick(b)
		b._force_repath = true
	elif not b._flank_flipped:
		b._flank_angle += PI
		b._flank_flipped = true
		b._force_repath = true
	else:
		b._route = BotBrain.Route.DIRECT
		b._set_state(BotBrain.State.HUNT_DIRECT)
		b._force_repath = true
