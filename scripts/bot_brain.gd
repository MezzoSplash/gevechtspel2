class_name BotBrain
extends RefCounted
## Server-only AI. Same Player movement helpers. Gun choice changes fight distance.

const ACQUIRE := 0.28
## Only used before a bot has a weapon in hand (a gun's own fight range lives in its .tres).
const NO_GUN_FIGHT := 13.0
const STRAFE_SPEED := 6.2
## One committed sidestep, then a short pause. Re-picking every half second is what made them shimmy.
## How long that commit lasts is per character now (`BotStyle.strafe_hold_min/max`, #267).
const STRAFE_PAUSE_MIN := 0.30
const STRAFE_PAUSE_MAX := 0.55
const STRAFE_PROBE := 1.2 # metres of open space a new sidestep needs
const STRAFE_KEEP := 0.9 # while committed: stop at a wall or a ledge, ignore a crate further out
const STRAFE_FLOOR := 2.0 # down-ray; a miss is a ledge
const MAX_STEP_SLOPE := 46.0 # same cap as the navmesh bake
const SHOT_MASK := 1 | 2
const WORLD_MASK := 1 # arena only; pawns are layer 2 and do not block each other
const MELEE_R := 1.8 # enemy this close (feet to feet) gets bashed instead of shot
## #269: Hard only. An empty gun is walked to a hidden spot inside this radius. One round left
## and the enemy already inside RELOAD_HOLD_R is a bash, not a reload in their face.
const COVER_R := 8.0
const RELOAD_HOLD_R := 6.0
const COVER_SAMPLES := 8
const COVER_REACHES: Array[float] = [3.0, 5.5, 8.0]
const RETARGET := 0.25 # seconds between target picks (each pick costs up to 5 rays)
const SEPARATION_R := 1.3 # push away from any pawn closer than this
const STUCK_CHECK := 1.0
const STUCK_DIST := 0.4
const UNSTICK_TIME := 0.6
const HUNT_REPATH := 0.9 # seconds a hunt path is kept before asking again
const HUNT_SHIFT := 8.0 # enemy moved this far: the old path is about the wrong place
## #150: who just shot us wins over a closer stranger, for a few seconds.
const THREAT_TIME := 3.0
## A hit below the character's own HP limit (BotStyle.retreat_hp, #267) is a break-off, not a
## stand-and-trade. Short on purpose: they sprint away and come back from the other side, they do not
## camp the corner.
const RETREAT_TIME := 0.9
const RETREAT_CD := 5.0
## Step-up clears a curb (0.32 m). Taller than that, up to what JUMP_SPEED actually
## clears under gravity 22, is a jump. A walkable ramp is rejected by its face slope.
const JUMP_CLEAR_MIN := 0.36
const JUMP_CLEAR_MAX := 1.15
## Hand wobble around the aim point (metres at the target), so a correct aim is not an aimbot.
const AIM_WOBBLE_BASE := 0.85
const AIM_WOBBLE_PER_M := 0.012 # wider with distance
const AIM_WOBBLE_PER_SPEED := 0.07 # and when the target moves (per m/s)
const AIM_WOBBLE_FRESH := 1.8 # first moments on a new target
const AIM_WOBBLE_REPICK := 0.3
const AIM_TRACK := 14.0 # how fast the aim catches up with a moving target (1/s)
## Per-gun aim feel (the SMG's wider hand and slower track, the fight ranges, the bursts) lives in
## the gun's own WeaponDef/.tres. Nothing in this file branches on a gun id any more.

var pawn: Player
var agent: NavigationAgent3D
var _acquire_left := ACQUIRE # set from Game.bot_profile() (#90) when a target is picked
## Slide, wallrun and dive run through the same Movement code as a human's. These are the bot's keys:
## crouch is held for the length of a slide, and pressed for a single tick so Movement sees a real press.
const BOT_SLIDE_HOLD := 0.45 # s of crouch hold for one slide
## The slide band is per character now (BotStyle.slide_min_m/slide_max_m, #267 slice 2).
const BOT_DIVE_RANGE := 14.0 # m: falling toward a target inside this range is worth a dive
var _crouch_hold := 0.0
var _crouch_press := false
var _strafe_sign := 1.0
var _strafe_hold := 0.0
var _strafe_pause := 0.0
var _seen_target = null # untyped: may be freed. Last pawn _can_see found, and where (body or head)
var _seen_point := Vector3.ZERO
var _aim_err := Vector2.ZERO # current wobble (sideways, up) in metres, eased toward _aim_err_goal
var _aim_err_goal := Vector2.ZERO
var _aim_err_t := 0.0
var _aim_track := Vector3.ZERO # lagged aim point (world)
var _aim_for = null # untyped: may be freed. Target the wobble was rolled for
var _repath_t := 0.0
var _burst_left := 0
var _burst_pause := 0.4
var _home := Vector3.ZERO
var _target: Player
var _retarget_t := 0.0
var _wants_move := false
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_pulse := false # set for the tick that noticed no progress
var _unstick_left := 0.0
var _unstick_dir := Vector3.ZERO
## What the bot is doing this tick. One value replaces `_in_fight` and the hunt/direct chase, which
## used to be two booleans that could contradict each other, and it is what `_tick_tricks` reads when
## it decides whether closing on the target is worth a slide.
enum State { IDLE, PATROL, OBJECTIVE, HUNT_FLANK, HUNT_DIRECT, FIGHT, RETREAT, COVER, RC }
## Which way the current chase goes. It is only ever read by the hunt, never by what the bot does this
## tick: an interruption on the way (a cover reload, a CTF objective, the RC-XD) leaves it alone, so the
## chase comes back the way it went. A new target, a retreat or a fresh fight puts it back on the flank.
enum Route { FLANK, DIRECT }
var state: State = State.IDLE
var _route: Route = Route.FLANK
## #272: line of sight, answered once per `los_ttl` physics ticks per enemy. See `_can_see()`.
var _los: Dictionary = {} # instance id -> {"vis": bool, "point": Vector3, "frame": int}
## How many physics ticks a line-of-sight answer stays valid. The measured trade-off (16 bots, 120
## ticks, `tools/check_bot_perf`, two runs): 1 tick = 10-15% fewer rays, 2 = 33%, 4 = 50-66%,
## 6 = 53-67%, 9 = 59-77%. Six ticks is 0.1 s at 60 Hz - under the profile's own acquire time
## (0.28 s), so a bot never reacts to a stale answer faster than it reacts to anything, and it keeps
## the >=50% goal out of reach of run-to-run noise.
var los_ttl := 6
## Bounds the cache: a pawn that respawns gets a new instance id, so entries are pruned by size too.
const LOS_CACHE_MAX := 64
## Rays fired by `_can_see()`. Only counted while `count_rays` is on, which is what
## `tools/check_bot_perf` flips: production should not pay for a counter nobody reads.
static var los_rays := 0
static var count_rays := false
var los_cache := true
## #267: this bot's character (aggressive / holder / chaos), from `data/bots/*.tres`. Difficulty is
## how good it is; this is what it wants to do. Set in `setup()`, stable across a respawn.
var style: BotStyle
## #270: the authored route being followed, if any - {"kind", "points"} plus a cursor. A route is a
## plan (a wallrun alley, a slide chain); it is dropped the moment it stops making progress.
var _hint: Dictionary = {}
var _hint_i := 0
var _hint_pos := Vector3.ZERO
var _hint_t := 0.0
## A slide route presses crouch exactly once, at the start of the route: every tick would keep the
## bot crouched (slow) without ever gaining the speed that starts the slide.
var _hint_pressed := false
## #267/#250: this bot's own roll series, seeded by slot, so a test run can replay a character.
var rng := RandomNumberGenerator.new()
## How long this character has wanted to shoot but did not have the angle yet (#267 slice 2).
var _flank_wait := 0.0
const FLANK_SIGHT_GRACE := 0.8 # s (#382): a shorter loss of sight keeps the flanker's patience
var _flank_lost := 0.0 # s without sight, so a corner does not wipe the flanker's patience (#382)
var _flank_base := 0.0 # peer slot on the ring; restored when the target changes
var _flank_angle := 0.0 # radians around the enemy; hunt aims here before closing
var _flank_flipped := false # first stuck tries the other side before a direct chase
var _path_live := false # a target has been handed to the agent this chase
var _path_enemy := Vector3.ZERO # where the enemy stood when that path was built
var _force_repath := false
## #267 slice 2: a flanker this close is about to be shanked, so angle or not, it shoots. A ring point
## it has already reached is worth leaving - at a rate of `flank_switch_per_s` per second.
## #270: a route point counts as reached this close, and a route without HINT_STALL_DIST of progress
## inside HINT_STALL seconds is dropped - the issue's 0.6 s, so a broken route never hangs a bot.
const HINT_ARRIVE := 2.0
const HINT_STALL := 0.6
const HINT_STALL_DIST := 0.5
const FLANK_ARRIVE := 3.0 # m: close enough to the ring point that standing there is standing still
const FLANK_POINT_BLANK := 2.5
const FLANK_TURN := PI * 0.5
## Grenades: frags at mid range, a cooldown so they do not spam.
const NADE_MIN := 7.0
const NADE_MAX := 21.0
const NADE_COOLDOWN_MIN := 7.0
const NADE_COOLDOWN_MAX := 14.0
## Per character: `BotStyle.nade_chance` (#267). A holder never throws one.
const NADE_CHECK := 0.6
const NADE_ARC_STEPS := 8 # rays along the toss, only when a throw is about to happen
var _nade_cd := 3.0
var _nade_check := 0.0
## Scorestreaks: the same UAV (3) and RC-XD (5) the players earn. The RC is driven from here through
## the car's public input (the same call a remote driver's packets use); rc_xd.gd is unchanged.
const STREAK_USE_DELAY := 1.2 # beat between earning and using, so it reads as a choice
const RC_BLOW_R := 2.6 # detonate this close to an enemy
const RC_LAUNCH_MIN := 12.0 # only send the car at someone this far or farther (or out of sight)
var _streak_wait := 0.0
var _rc_repath := 0.0
var _rc_point := Vector3.ZERO
var _threat = null # untyped: may be freed. Pawn that last damaged us
var _threat_left := 0.0
var _hurt_retreat_left := 0.0
var _retreat_cd := 0.0
## #269: one hide spot for the current reload. Cleared when the mag is full again.
var _cover_live := false
var _cover_point := Vector3.ZERO
var _cover_flee := false
## Awareness (see Game.BOT_PROFILES: omni / memory / hear). A bot that is not omniscient only knows an
## enemy it saw, was shot by, or heard fire close by, and hunts the last place it knew them.
const HEAR_MS := 1200 # a shot this recent still counts as heard at the next retarget
const HEAR_ERROR := 3.0 # m: where a shot seems to come from is off by up to this much
const SEARCH_ARRIVE := 3.0 # m: at the last known spot and nobody there: forget them
const PATROL_TIME := 10.0 # s: a patrol point is dropped after this long, reached or not
const PATROL_ARRIVE := 3.0
## instance id of an enemy -> {"pos": last known position, "left": seconds until it is forgotten}.
var _known := {}
var _patrol_point := Vector3.ZERO
var _patrol_t := 0.0
## Wall tricks (BotWall finds the wall from raycasts; Game.BOT_PROFILES `trick` is the chance per wall met).
## NONE -> jump toward a wall (AIR) -> wallrun (RUN) -> wall jump off at the end -> NONE.
enum Trick { NONE, AIR, RUN }
const TRICK_SCAN := 0.4 # s between wall scans while running the floor (1 ray fan each, up to 12 rays)
const TRICK_CD := 5.0 # s after a trick ends (done or failed) before the next one
const TRICK_SKIP_CD := 3.0 # s a bot leaves a wall alone after the dice said no (not re-rolled every scan)
const TRICK_MIN_SPEED := 9.0 # m/s flat: 0.82 of it must still reach WALLRUN_MIN_SPEED (6.5) along the wall
const TRICK_AIR_MAX := 0.9 # s in the air without a wallrun starting: give up and land
const TRICK_JUMP_AT := 0.9 # s of wallrun before the wall jump (the run itself lasts WALLRUN_TIME 1.25 s)
var _trick := Trick.NONE
var _trick_t := 0.0
var _trick_cd := 0.0
var _trick_scan_t := 0.0
var _trick_plan := {}


func setup(p: Player, nav: NavigationAgent3D) -> void:
	pawn = p
	agent = nav
	style = BotStyle.for_peer(p.peer_id)
	_flank_wait = 0.0 # a new life starts with a clean patience clock
	# #267: one roll series per bot, seeded by slot. Deterministic per slot now; #250 makes it
	# deterministic per match by reseeding this at match start.
	rng.seed = absi(p.peer_id)
	# The name stays off the scoreboard (a player should not read the tactic off it), but a test run
	# has to be able to count characters, so it goes to the server log once per spawn.
	if p.is_bot and (Game.is_offline or Game.multiplayer.is_server()):
		print("[bot] %s is %s" % [p.name, style.display_name])
	_home = p.global_position
	_stuck_pos = p.global_position
	_strafe_sign = -1.0 if randf() < 0.5 else 1.0
	# Stable ring slot so the squad does not file through one door.
	_flank_base = float(absi(p.peer_id) % 8) / 8.0 * TAU
	_flank_angle = _flank_base
	_burst_pause = randf_range(0.25, 0.7)


## Hunt if no LOS, strafe+shoot if visible. Shotgun bots push closer than rifle.
func physics_tick(delta: float) -> void:
	if pawn == null:
		return
	if style == null:
		style = BotStyle.for_peer(pawn.peer_id) # a brain built by hand in a check has no character yet
	pawn.is_sprinting = false
	_retreat_cd = maxf(_retreat_cd - delta, 0.0)
	_threat_left = maxf(_threat_left - delta, 0.0)
	_hurt_retreat_left = maxf(_hurt_retreat_left - delta, 0.0)
	_tick_memory(delta)
	if _threat_left <= 0.0:
		_threat = null
	if pawn.is_dead:
		_known.clear() # a new life starts without knowing where anyone is
		_end_wall_trick() # nor halfway up a wall
		pawn.velocity = Vector3.ZERO
		return
	if Game.play_locked():
		pawn.velocity.x = 0.0
		pawn.velocity.z = 0.0
		if not pawn.is_on_floor():
			pawn.velocity.y += float(pawn.get_gravity().y) * delta
		pawn.move_and_slide()
		return
	if pawn.is_lunging():
		_move(delta)
		return
	_burst_pause = maxf(_burst_pause - delta, 0.0)
	_nade_cd = maxf(_nade_cd - delta, 0.0)
	if not pawn.is_on_floor():
		pawn.velocity.y += float(pawn.get_gravity().y) * delta
	else:
		pawn.velocity.y = 0.0
	if _drive_rc(delta):
		return
	_track_stuck(delta)
	var enemy := _pick_target(delta)
	_tick_streaks(delta, enemy)
	# #150: low HP after a hit. Sprint out, then the flipped flank brings them back in.
	if _hurt_retreat_left > 0.0 and enemy != null:
		_set_state(State.RETREAT)
		var away := pawn.global_position - enemy.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -pawn.transform.basis.z
			away.y = 0.0
		away = away.normalized()
		_face_travel(away)
		_steer_to(pawn.global_position + away * 6.0, Player.SPRINT_SPEED, delta, false)
		_move(delta)
		return
	# #269: empty mag on Hard. Kept even after LOS breaks, or the hunt walks them back into the open
	# while the reload is still running. Easy and Medium fall through and reload where they stand.
	if enemy != null and _should_cover_reload(enemy):
		_set_state(State.COVER)
		_tick_cover_reload(enemy, delta)
		_move(delta)
		return
	_cover_live = false
	var goal := CTF.bot_goal(Game, pawn) # #160: Vector3.INF outside CTF
	if enemy == null or (goal != Vector3.INF and not _can_see(enemy)):
		_acquire_left = float(Game.bot_profile().acquire)
		if _stuck_pulse:
			_pick_unstick()
		if goal != Vector3.INF:
			_set_state(State.OBJECTIVE)
			_go_to_objective(goal, delta)
		elif _omniscient():
			_set_state(State.IDLE)
			_steer_to(_home, Player.WALK_SPEED, delta)
		else:
			_set_state(State.PATROL)
			_patrol(delta) # nobody known: look around instead of standing at the spawn
		_move(delta)
		return
	# Seen but out of weapon range (a shotgun bot at a window, the enemy across the street): sprint the
	# navmesh toward him instead of pushing straight at him into the wall.
	var out_of_range := pawn.global_position.distance_to(enemy.global_position) > _fight_range() + 4.0
	var seen := _can_see(enemy)
	var fighting := seen and not out_of_range
	if style.flank_only:
		_tick_flank_sight(seen, delta)
	if fighting and style.flank_only:
		fighting = _flank_aim_ok(enemy, delta) # #267: the flanker does not open fire from the front
	if fighting:
		_set_state(State.FIGHT)
		_acquire_left = maxf(_acquire_left - delta, 0.0)
		_fight(enemy, delta)
	else:
		_acquire_left = float(Game.bot_profile().acquire)
		# #270: an authored route beats the generic path while it lasts; without one (or when it is
		# dropped) the hunt below is exactly what it always was.
		if _hint.is_empty():
			_try_pick_hint(enemy)
		if _hint.is_empty():
			_hunt(enemy, delta)
		else:
			# A route is a hunt: left on FIGHT, the wall trick refused to start on it.
			_set_state(State.HUNT_DIRECT if _route == Route.DIRECT else State.HUNT_FLANK)
			_follow_hint(enemy, delta)
	_move(delta)


## move_and_slide plus the same small step-up the players get (StepUp), so bots do not stall on a lip.
## Before it moves: slide, wallrun and dive, through the very same Movement code a human runs.
func _move(delta: float) -> void:
	if pawn.is_lunging():
		pawn.consume_lunge(delta)
		if not pawn.is_on_floor():
			pawn.velocity.y += float(pawn.get_gravity().y) * delta
		pawn.move_and_slide()
		return
	_tick_tricks(delta)
	var pre := pawn.velocity
	var was_floor := pawn.is_on_floor()
	pawn.move_and_slide()
	StepUp.try_step(pawn, pre, was_floor, delta)


## The bot's keys for this tick. Sprint whenever it wants to move; crouch only for a slide or a dive.
## Movement reads these off the pawn, which is what lets it run for a bot at all (no keyboard here).
func _set_bot_input() -> void:
	pawn._in_sprint = true
	pawn._in_crouch = _crouch_hold > 0.0 or _crouch_press
	pawn._in_crouch_down = _crouch_press
	_crouch_press = false


## Slide into a fight, wallrun along a wall, dive at a target below. All three go through Movement, so a
## bot obeys exactly the same ranges, cooldowns and physics as the player.
func _tick_tricks(delta: float) -> void:
	BotTricks.tick(self, delta)


## Wall trick, one step per tick. Runs before the slide/dive keys and Movement.tick_wallrun, which do the
## actual wallrun (the same code a human runs); this only decides to jump at a wall, and when to jump off.
func _tick_wall_trick(delta: float, on_floor: bool, has_foe: bool) -> void:
	BotTricks.tick_wall_trick(self, delta, on_floor, has_foe)


## On the floor and sprinting along the path: a wall alongside the heading, and the dice, start a trick.
func _try_start_wall_trick() -> void:
	BotTricks.try_start_wall_trick(self)


## Keeps the horizontal velocity on the entry line (toward the wall) while the bot is in the air.
func _aim_into_wall() -> void:
	BotTricks.aim_into_wall(self)


func _end_wall_trick() -> void:
	BotTricks.end_wall_trick(self)


## Nearest enemy we can actually see; else the nearest one to hunt. Re-picked every RETARGET.
## Closest-only used to lock bots onto someone hidden behind a teammate (issue #1: the pile in the middle).
func _pick_target(delta: float) -> Player:
	_retarget_t -= delta
	if _retarget_t > 0.0 and _valid_target(_target) and _knows(_target):
		# Still look now when the pawn who shot us is in sight and not the current target.
		if not (_valid_target(_threat) and _target != _threat and _can_see(_threat)):
			return _target
	_retarget_t = RETARGET
	var enemies := _enemies_by_distance()
	_listen(enemies)
	var prev := _target
	_target = null
	# #150: the shooter, if we can see them, even when someone else is closer.
	if _valid_target(_threat) and _can_see(_threat):
		_target = _threat
	else:
		for e in enemies:
			if _can_see(e):
				_target = e
				break
	if _target == null and _valid_target(_threat) and _knows(_threat):
		_target = _threat # hunt the one who shot, not whoever is nearest through a wall
	elif _target == null:
		_target = _nearest_known(enemies) # null when nobody is known: the bot patrols
	if _target != prev:
		_reset_hunt()
	return _target


## #150: a hit from another pawn. Prefer them as the target, and break off the trade when low.
func note_threat(attacker: Player) -> void:
	if not _valid_target(attacker):
		return
	_threat = attacker
	_threat_left = THREAT_TIME
	_retarget_t = 0.0
	_remember(attacker, attacker.global_position) # being hit tells you where it came from
	if style.retreat_hp > 0.0 and Game.hp_of(pawn) <= style.retreat_hp and _retreat_cd <= 0.0:
		_hurt_retreat_left = RETREAT_TIME
		_retreat_cd = RETREAT_CD
		_set_state(State.RETREAT)
		# The flipped flank is what brings them back in from the other side.
		_route = Route.FLANK
		_flank_angle += PI
		_flank_flipped = true
		_drop_path()


## Untyped on purpose: a freed pawn in a typed Player argument is a runtime error.
func _valid_target(p) -> bool:
	return (
		is_instance_valid(p)
		and not p.is_queued_for_deletion()
		and not p.is_dead
		and (p.team_id != pawn.team_id or Game.is_ffa())
		and p != pawn
	)


## Hard bots know where everyone is, through walls: how every bot played before awareness existed.
func _omniscient() -> bool:
	return bool(Game.bot_profile().omni)


## Does this bot know where `e` is? Untyped like _valid_target: check validity first, the pawn may be freed.
func _knows(e) -> bool:
	return _omniscient() or _known.has(e.get_instance_id())


## Where the bot thinks `e` is: the real spot when omniscient, else the last place it knew them.
## Callers must have checked `_knows(e)` first: with no memory entry this returns the real position, so
## asking about an enemy this bot does not know would read as seeing through walls.
func _goal_pos(e) -> Vector3:
	if not _omniscient():
		var k: Dictionary = _known.get(e.get_instance_id(), {})
		if not k.is_empty():
			return k["pos"] as Vector3
	return e.global_position


## Seen, shot by, or heard: the bot now knows `pos` for `secs` (default: the profile's memory).
func _remember(e, pos: Vector3, secs: float = -1.0) -> void:
	if _omniscient() or not is_instance_valid(e):
		return
	if secs < 0.0:
		secs = float(Game.bot_profile().memory)
	_known[e.get_instance_id()] = {"pos": pos, "left": secs}


## Nobody at the last known spot: drop them and make the next pick start fresh.
func _forget(e) -> void:
	if is_instance_valid(e):
		_known.erase(e.get_instance_id())
	if _target == e:
		_target = null
		_retarget_t = 0.0
		_drop_route()


## Memory fades; a freed pawn is dropped at once.
func _tick_memory(delta: float) -> void:
	for id in _known.keys():
		var k: Dictionary = _known[id]
		k["left"] = float(k["left"]) - delta
		if float(k["left"]) <= 0.0 or not is_instance_valid(instance_from_id(id)):
			_known.erase(id)


## Shots fired within the profile's `hear` radius give the shooter away, with a few metres of error.
func _listen(enemies: Array[Player]) -> void:
	if _omniscient():
		return
	var r := float(Game.bot_profile().hear)
	var now := Time.get_ticks_msec()
	for e in enemies:
		if now - e.last_shot_ms > HEAR_MS:
			continue
		if pawn.global_position.distance_to(e.global_position) > r:
			continue
		var err := Vector3(randf_range(-HEAR_ERROR, HEAR_ERROR), 0.0, randf_range(-HEAR_ERROR, HEAR_ERROR))
		_remember(e, e.global_position + err)


## The enemy closest to where we think they are (omniscient bots: the closest one, as before).
func _nearest_known(enemies: Array[Player]) -> Player:
	var best: Player = null
	var best_d := INF
	for e in enemies:
		if not _knows(e):
			continue
		var d := pawn.global_position.distance_squared_to(_goal_pos(e))
		if d < best_d:
			best_d = d
			best = e
	return best


## Nobody known: roam the navmesh. Random points leak nothing about where the enemy is.
func _patrol(delta: float) -> void:
	_patrol_t -= delta
	var here := pawn.global_position
	var flat := Vector2(here.x - _patrol_point.x, here.z - _patrol_point.z).length()
	if _patrol_t <= 0.0 or flat < PATROL_ARRIVE or _stuck_pulse:
		_patrol_t = PATROL_TIME
		_patrol_point = _random_nav_point()
	_go_to_objective(_patrol_point, delta)


## A random walkable point on the bot's navigation map. `Vector3.ZERO` means "the map had none" — a real
## point is never exactly the origin — and the caller then keeps its home.
func _random_nav_point() -> Vector3:
	if agent == null:
		return _home
	var p := NavigationServer3D.map_get_random_point(agent.get_navigation_map(), agent.navigation_layers, true)
	return p if p != Vector3.ZERO else _home


## No progress for STUCK_CHECK while trying to move. The caller decides: a new flank, or a nudge.
func _track_stuck(delta: float) -> void:
	_stuck_pulse = false
	_unstick_left = maxf(_unstick_left - delta, 0.0)
	_stuck_t += delta
	if _stuck_t < STUCK_CHECK:
		return
	_stuck_t = 0.0
	var moved := pawn.global_position.distance_to(_stuck_pos)
	_stuck_pos = pawn.global_position
	if moved < STUCK_DIST and _wants_move and _unstick_left <= 0.0:
		_stuck_pulse = true


## Soft push away from pawns that are too close, so bots do not stack up in doorways.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for p in Game.players(): # #272: one roster per tick, not a group array per bot
		if p == pawn or p.is_dead:
			continue
		var away := pawn.global_position - p.global_position
		away.y = 0.0
		var d := away.length()
		if d >= SEPARATION_R:
			continue
		if d < 0.01:
			away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			d = 0.01
		push += away.normalized() * (1.0 - d / SEPARATION_R)
	return push


## The one place in the bot that writes `state`; the two check fixtures set the field directly.
## It also does the setup the new state needs and clears what belonged to the old one: a fight starts
## on a fresh sidestep with no hunt path left over, and every other state has no strafe commit to keep.
func _set_state(s: State) -> void:
	if s == state:
		return
	_strafe_hold = 0.0
	_strafe_pause = 0.0
	if s == State.FIGHT:
		_unstick_left = 0.0
		_drop_route()
	state = s


## Forget the route of this chase: the flank approach again, and no path from the old one.
## The peer keeps its flank side — a fresh fight does not re-roll it.
func _drop_route() -> void:
	_route = Route.FLANK
	_drop_path()


## No path handed to the agent; the next leg asks the navmesh again.
func _drop_path() -> void:
	_path_live = false
	_force_repath = true


## A whole new chase: the peer's own flank slot, no path, no stuck history.
func _reset_hunt() -> void:
	_flank_wait = 0.0 # a new target has not yet earned a break-off shot
	_clear_hint() # a route to the old target says nothing about the new one
	_drop_route()
	_flank_flipped = false
	_flank_angle = _flank_base
	_repath_t = 0.0


## #270: look for an authored route worth taking right now. Cheap when the map ships none (one cached
## look-up that returns an empty list) and skipped entirely while a route is already being followed.
func _try_pick_hint(enemy: Player) -> void:
	var space := pawn.get_world_3d().direct_space_state
	var routes := BotRoutes.for_map(space, Game.map_id)
	if routes.is_empty():
		return
	var h := BotRoutes.pick(space, routes, pawn.global_position, _goal_pos(enemy))
	if h.is_empty():
		return
	_hint = h.duplicate(true)
	_hint_i = 1
	_hint_pos = pawn.global_position
	_hint_t = 0.0
	_hint_pressed = false


## Walk one authored route. The kind only decides the keys: a slide route presses crouch once at the
## start, a wallrun or surf route is run at sprint straight at the next point and the movement code
## (#278's wall trick, the surf state) takes over when the geometry offers it.
func _follow_hint(enemy: Player, delta: float) -> void:
	var pts: Array = _hint.get("points", [])
	if _hint_i >= pts.size():
		_clear_hint()
		return
	var dest: Vector3 = pts[_hint_i]
	if Vector2(dest.x - pawn.global_position.x, dest.z - pawn.global_position.z).length() < HINT_ARRIVE:
		_hint_i += 1
		_hint_pos = pawn.global_position
		_hint_t = 0.0
		if _hint_i >= pts.size():
			_clear_hint() # the route delivered us: the hunt takes it from here
			return
		dest = pts[_hint_i]
	# No progress: a route that does not move the bot is worse than no route at all.
	_hint_t += delta
	if pawn.global_position.distance_to(_hint_pos) > HINT_STALL_DIST:
		_hint_pos = pawn.global_position
		_hint_t = 0.0
	elif _hint_t >= HINT_STALL:
		_clear_hint()
		return
	# A slide needs speed to start: pressing crouch while walking just crouches the bot and it crawls
	# the rest of the route at a walk - measured in check_bot_route (11 m/s -> 1 m/s -> stall).
	var fast := Vector2(pawn.velocity.x, pawn.velocity.z).length() >= Player.SPRINT_SPEED * 0.9
	if (StringName(_hint.get("kind", &"")) == &"slide"
			and fast and not _hint_pressed and pawn.is_on_floor()
			and _crouch_hold <= 0.0 and _crouch_press == false and pawn._slide_cd <= 0.0):
		_hint_pressed = true
		_crouch_press = true
		_crouch_hold = BOT_SLIDE_HOLD
	_tick_aim_wobble(enemy, delta)
	_face_travel(dest - pawn.global_position)
	_steer_to(dest, Player.SPRINT_SPEED, delta, false)


func _on_wall_route() -> bool:
	return StringName(_hint.get("kind", &"")) == &"wallrun"


func _clear_hint() -> void:
	_hint = {}
	_hint_i = 0
	_hint_t = 0.0
	_hint_pressed = false


## No line of sight, or seen but outside gun range. Follow the navmesh.
## First to a point beside the enemy (different bots, different doors), then to their feet.
func _hunt(enemy: Player, delta: float) -> void:
	if _route == Route.DIRECT:
		_hunt_direct(enemy, delta)
	else:
		_hunt_flank(enemy, delta)


## Flank: aim for a point on the ring around the enemy, so two bots do not file through one door.
## A path that runs out means the ring point was useless, and the chase goes straight at them.
func _hunt_flank(enemy: Player, delta: float) -> void:
	_set_state(State.HUNT_FLANK)
	_hunt_begin()
	var at := _goal_pos(enemy)
	# A ring point it has already reached is worth leaving (#267 slice 2): the flanker takes the next
	# angle on the enemy instead of standing on the spot, which is what "slaat vaker een hoek om" is.
	if (style.flank_switch_per_s > 0.0
			and pawn.global_position.distance_to(_flank_point(at)) < FLANK_ARRIVE
			and rng.randf() < 1.0 - exp(-style.flank_switch_per_s * delta)):
		_flank_angle += FLANK_TURN * (1.0 if rng.randf() < 0.5 else -1.0)
		_flank_flipped = false # a new angle is a new chase, not an escalation
		_drop_path()
	# is_navigation_finished is still true the frame a target is set; the path arrives after.
	var followed := _path_live and _repath_t < HUNT_REPATH - 0.2
	if followed and agent and agent.is_navigation_finished():
		_route = Route.DIRECT
		_set_state(State.HUNT_DIRECT)
		_force_repath = true
	_hunt_leg(enemy, delta, at if _route == Route.DIRECT else _flank_point(at), at)


## Direct: the enemy's feet, from wherever the flank left us.
func _hunt_direct(enemy: Player, delta: float) -> void:
	_set_state(State.HUNT_DIRECT)
	_hunt_begin()
	var at := _goal_pos(enemy)
	_hunt_leg(enemy, delta, at, at)


## Both halves start here: a target with no path yet asks the navmesh, a stuck hunt escalates.
func _hunt_begin() -> void:
	if not _path_live:
		_force_repath = true
	if _stuck_pulse:
		_on_hunt_stuck()


## One leg of the chase. `at` is where we think the enemy is: the path is remembered against it,
## so a target that moved further than HUNT_SHIFT makes us plan again instead of walking on.
func _hunt_leg(enemy: Player, delta: float, dest: Vector3, at: Vector3) -> void:
	var shifted := (
		_path_live
		and _path_enemy.distance_squared_to(at) > HUNT_SHIFT * HUNT_SHIFT
	)
	_repath_t -= delta
	# Keep the enemy's height. Snapping to our own y picks the floor under a roof, so the
	# path never takes the ramp when someone is standing up there. Steering still ignores y.
	if agent and (_repath_t <= 0.0 or shifted or _force_repath):
		agent.target_position = dest
		_path_enemy = at
		_path_live = true
		_repath_t = HUNT_REPATH
		_force_repath = false
	var travel := dest - pawn.global_position
	if agent and not agent.is_navigation_finished():
		travel = agent.get_next_path_position() - pawn.global_position
	# Keep the aim warm, but look along the path. Facing the enemy here is the moonwalk.
	_tick_aim_wobble(enemy, delta)
	_face_travel(travel)
	# Closing the gap at a walk is what made a chase look like a stroll. Shots stay
	# in the fight, where the wish speed is the strafe, so sprint does not tighten aim.
	_steer_to(dest, Player.SPRINT_SPEED, delta, true)
	# Reached the last known spot and nobody is in sight: they moved on. Forget them and look elsewhere.
	if not _omniscient():
		var flat := Vector2(pawn.global_position.x - at.x, pawn.global_position.z - at.z).length()
		if flat < SEARCH_ARRIVE and not _can_see(enemy):
			_forget(enemy)


## #160: walk the navmesh to a CTF goal (flag, base). Repaths when the goal moves or every HUNT_REPATH.
func _go_to_objective(goal: Vector3, delta: float) -> void:
	_repath_t -= delta
	if agent and (_repath_t <= 0.0 or _path_enemy.distance_squared_to(goal) > 4.0):
		agent.target_position = goal
		_path_enemy = goal
		_repath_t = HUNT_REPATH
	var travel := goal - pawn.global_position
	if agent and not agent.is_navigation_finished():
		travel = agent.get_next_path_position() - pawn.global_position
	_face_travel(travel)
	_steer_to(goal, Player.SPRINT_SPEED, delta, true)


## Hard reloads out of sight. Easy and Medium do not: the flag lives on the difficulty profile.
func _seeks_cover() -> bool:
	return BotCover.seeks_cover(self)


## Empty or already reloading, and not close enough that a bash is the better use of the moment.
func _should_cover_reload(enemy: Player) -> bool:
	return BotCover.should_reload(self, enemy)


## The last round, inside RELOAD_HOLD_R. Shooting it is what would start the reload.
func _hold_last_round(dist: float) -> bool:
	return BotCover.hold_last_round(self, dist)


## Sprint to the hide spot chosen when the reload started. No spot: back to the enemy, same sprint.
func _tick_cover_reload(enemy: Player, delta: float) -> void:
	BotCover.tick_reload(self, enemy, delta)


## Nearest standable spot within COVER_R that the enemy's chest cannot see. The rays run once per
## reload, not per tick. A heading whose first step is a wall is skipped (`_side_open`). INF: flee.
func _pick_cover(enemy: Player) -> Vector3:
	return BotCover.pick(self, enemy)


func _cover_floor(space: PhysicsDirectSpaceState3D, spot: Vector3) -> bool:
	return BotCover.floor_ok(self, space, spot)


## Visible and in range. Sidestep in the open; do not ask the navmesh for a 2 m shuffle.
func _fight(enemy: Player, delta: float) -> void:
	if _def() != null and _def().melee:
		_fight_shank(enemy, delta)
		return
	_tick_aim_wobble(enemy, delta)
	_face(enemy)
	var away := pawn.global_position - enemy.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = pawn.transform.basis.z
		away.y = 0.0
	away = away.normalized()
	var side := Vector3.UP.cross(away)
	side.y = 0.0
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	# Grinding a wall ends the commit so the probe can pick the open side.
	if _stuck_pulse:
		_strafe_hold = 0.0
		_strafe_pause = 0.0
	if _strafe_hold <= 0.0 and _strafe_pause <= 0.0:
		_pick_strafe_side(side)
	var dist := pawn.global_position.distance_to(enemy.global_position)
	# One round left and they are already on top of us: close and bash. Spending it starts a reload.
	if _hold_last_round(dist):
		if dist > MELEE_R:
			_steer_to(pawn.global_position - away * 4.0, Player.SPRINT_SPEED, delta, false)
		if _acquire_left <= 0.0 and dist <= MELEE_R:
			Game.melee.swing(pawn)
		return
	# This character's preferred distance, but never outside the range it is willing to shoot from.
	var fight_r := minf(_fight_range() * style.range_scale, _fight_range() + BotStyle.CLOSE_ENOUGH_M)
	var wish := Vector3.ZERO
	if _strafe_pause > 0.0:
		_strafe_pause = maxf(_strafe_pause - delta, 0.0)
		# Almost still: only a step when the range is wrong, so the player gets a shot.
		if dist < style.back_off_m:
			wish = away
		elif dist > fight_r + style.hold_band:
			wish = -away
		if wish.length_squared() > 0.0001 and not _side_open(wish, STRAFE_KEEP):
			wish = Vector3.ZERO
	else:
		# The commit is long enough to walk off a roof. Cut it when the next step closes.
		var strafe_dir := side * _strafe_sign
		if not _side_open(strafe_dir, STRAFE_KEEP):
			_strafe_hold = 0.0
		else:
			_strafe_hold = maxf(_strafe_hold - delta, 0.0)
			wish = strafe_dir
			if dist < style.back_off_m:
				wish += away * 0.7
			elif dist > fight_r + style.hold_band:
				wish += -away * 0.7
			if wish.length_squared() > 1.0:
				wish = wish.normalized()
		if _strafe_hold <= 0.0:
			# Next commit tries the other side. The probe still rejects a wall.
			_strafe_sign *= -1.0
			_strafe_pause = randf_range(STRAFE_PAUSE_MIN, STRAFE_PAUSE_MAX)
	# Fight steering is the wish itself. A nav path for this point is what made them hobble.
	_steer_to(pawn.global_position + wish, STRAFE_SPEED, delta, false)
	if _acquire_left <= 0.0 and dist <= MELEE_R and Game.melee.swing(pawn):
		return
	if _acquire_left <= 0.0 and _try_grenade(enemy, dist, delta):
		return
	if _acquire_left <= 0.0 and dist <= fight_r + 4.0:
		_try_shoot(enemy)


## Shank: close the last metres and stab. No strafe-shoot. The lunge is inside swing_shank.
func _fight_shank(enemy: Player, delta: float) -> void:
	_tick_aim_wobble(enemy, delta)
	_face(enemy)
	var dist := pawn.global_position.distance_to(enemy.global_position)
	var away := pawn.global_position - enemy.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = pawn.transform.basis.z
		away.y = 0.0
	else:
		away = away.normalized()
	if dist > Melee.SHANK_CHASE:
		_steer_to(enemy.global_position, Player.SPRINT_SPEED, delta, true)
	else:
		_steer_to(pawn.global_position - away * 4.0, Player.SPRINT_SPEED, delta, false)
	if _acquire_left <= 0.0 and dist <= Melee.SHANK_RANGE + 0.8:
		Game.melee.swing_shank(pawn)


## Frag at a visible enemy in mid range. The pitch is solved so the arc lands near them before the fuse.
## A pitch whose arc hits the world (a ceiling, a lip, a door head) is refused, and the cooldown
## stays: the bot can try again on the next check instead of bouncing the frag into its own feet.
func _try_grenade(enemy: Player, dist: float, delta: float) -> bool:
	return BotGrenade.try_throw(self, enemy, dist, delta)


## Pitches that land within 2 m of the target, best error first. The +4 m/s is Grenade.initial_velocity.
func _grenade_pitches(from: Vector3, to: Vector3, d: float) -> Array[float]:
	return BotGrenade.pitches(self, from, to, d)


## Throw `pitch` if the arc is clear. False leaves the cooldown alone.
func _throw_pitched(from: Vector3, flat: Vector3, to: Vector3, pitch: float) -> bool:
	return BotGrenade.throw_pitched(self, from, flat, to, pitch)


## Eight rays along origin + v*t + ½gt², out to the target. Grenade.MASK, so a wall, a lip or an
## RC-XD blocks it. Pawns are excluded: the arc is aimed at one, and the fuse is a timer.
func _grenade_arc_clear(origin: Vector3, vel: Vector3, target: Vector3) -> bool:
	return BotGrenade.arc_clear(self, origin, vel, target)


## Banked UAV: use it after a short beat. Banked RC-XD: send it when the target is far or hidden.
## #317 slice 5: the streaks live in BotStreaks; the brain only keeps the state they update.
func _tick_streaks(delta: float, enemy: Player) -> void:
	BotStreaks.tick(self, delta, enemy)


func _drive_rc(delta: float) -> bool:
	return BotStreaks.drive_rc(self, delta)


## Does this character get to open fire on `enemy` from where it stands? Only the flanker asks
## (#267 slice 2): no attack from straight ahead, a free shot from the side or the back, and a
## patience timer so it never circles forever in front of someone who keeps facing it.
## #382: the flanker's patience only restarts after a real loss of sight. It used to restart on every
## single tick without sight, so a bot that kept dipping in and out of view (a corner, a crate, or a
## player who keeps turning to face it) never reached flank_patience and circled instead of firing.
func _tick_flank_sight(seen: bool, delta: float) -> void:
	if seen:
		_flank_lost = 0.0
		_flank_wait += delta
		return
	_flank_lost += delta
	if _flank_lost > FLANK_SIGHT_GRACE:
		_flank_wait = 0.0
		return
	# A short dip (a crate, a corner, the target turning) does not stop the clock: it used to throw the
	# whole patience away, which is why a flanker against a player who keeps facing it never fired.
	_flank_wait += delta


func _flank_aim_ok(enemy: Player, delta: float) -> bool:
	var to := pawn.global_position - enemy.global_position
	to.y = 0.0
	var facing := -enemy.transform.basis.z # the enemy's forward, flat
	facing.y = 0.0
	var from_side := true
	if facing.length_squared() > 0.0001 and to.length_squared() > 0.0001:
		# 1.0 is straight into the enemy's face, 0.0 is exactly the side.
		from_side = facing.normalized().dot(to.normalized()) < 0.35
	if from_side or pawn.global_position.distance_to(enemy.global_position) < FLANK_POINT_BLANK:
		_flank_wait = 0.0
		return true
	# The clock runs in _tick_flank_sight, so a flickering target cannot stretch the wait forever.
	return _flank_wait >= style.flank_patience


## Point on a ring around the enemy at fight range. Y stays theirs so roofs still route up a ramp.
func _flank_point(center: Vector3) -> Vector3:
	var dest := center
	dest.x += cos(_flank_angle) * _fight_range()
	dest.z += sin(_flank_angle) * _fight_range()
	return dest


## Stuck on a hunt path: other side of the enemy, then straight at them, then a short nudge.
func _on_hunt_stuck() -> void:
	if _route == Route.DIRECT:
		_pick_unstick()
		_force_repath = true
	elif not _flank_flipped:
		_flank_angle += PI
		_flank_flipped = true
		_force_repath = true
	else:
		_route = Route.DIRECT
		_set_state(State.HUNT_DIRECT)
		_force_repath = true


func _pick_unstick() -> void:
	for _i in 4:
		var a := randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		if _side_open(dir):
			_unstick_dir = dir
			_unstick_left = UNSTICK_TIME
			return
	_unstick_left = 0.0


## Prefer `side * sign` when that metre is walkable. Both closed: stand and shoot.
func _pick_strafe_side(side: Vector3) -> void:
	var prefer := side * _strafe_sign
	var open_prefer := _side_open(prefer)
	if not open_prefer and _side_open(-prefer):
		_strafe_sign *= -1.0
		open_prefer = true
	if open_prefer:
		_strafe_hold = randf_range(style.strafe_hold_min, style.strafe_hold_max)
		_strafe_pause = 0.0
	else:
		_strafe_hold = 0.0
		_strafe_pause = randf_range(STRAFE_PAUSE_MIN, STRAFE_PAUSE_MAX)


## True when a step along dir is not a wall and still has floor under it.
## `reach` is how far ahead to look. Picking a side looks further than the step that cuts a commit.
func _side_open(dir: Vector3, reach: float = STRAFE_PROBE) -> bool:
	dir.y = 0.0
	if dir.length_squared() < 0.0001 or pawn == null:
		return false
	dir = dir.normalized()
	var space := pawn.get_world_3d().direct_space_state
	var chest := pawn.global_position + Vector3.UP * 0.9
	var wall := PhysicsRayQueryParameters3D.create(chest, chest + dir * reach)
	wall.collision_mask = WORLD_MASK
	if not space.intersect_ray(wall).is_empty():
		return false
	var foot := pawn.global_position + dir * reach + Vector3.UP * 0.4
	var floor_q := PhysicsRayQueryParameters3D.create(foot, foot + Vector3.DOWN * STRAFE_FLOOR)
	floor_q.collision_mask = WORLD_MASK
	var hit := space.intersect_ray(floor_q)
	if not hit.has("normal"):
		return false
	var slope := rad_to_deg(acos(clampf((hit.normal as Vector3).dot(Vector3.UP), -1.0, 1.0)))
	# A few degrees of slack: a 46° ramp the navmesh accepts should not read as a wall.
	return slope <= MAX_STEP_SLOPE + 4.0


## Height of the lip in front of `wish`, or -1 when there is nothing to jump.
## Chest ray finds a face steeper than a walkable ramp. A second ray, from above
## the head down onto the far side, has to land on a top we can actually clear.
func _ledge_climb(wish: Vector3) -> float:
	if pawn == null:
		return -1.0
	wish.y = 0.0
	if wish.length_squared() < 0.0001:
		return -1.0
	var dir := wish.normalized()
	var space := pawn.get_world_3d().direct_space_state
	var origin := pawn.global_position
	var chest := origin + Vector3.UP * 0.45
	var wall_q := PhysicsRayQueryParameters3D.create(chest, chest + dir * 0.85)
	wall_q.collision_mask = WORLD_MASK
	wall_q.exclude = [pawn.get_rid()]
	var wall := space.intersect_ray(wall_q)
	if wall.is_empty() or not wall.has("normal"):
		return -1.0
	var slope := rad_to_deg(acos(clampf((wall.normal as Vector3).dot(Vector3.UP), -1.0, 1.0)))
	if slope <= MAX_STEP_SLOPE + 4.0:
		return -1.0
	var head_q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 1.0, origin + Vector3.UP * 2.1)
	head_q.collision_mask = WORLD_MASK
	head_q.exclude = [pawn.get_rid()]
	if not space.intersect_ray(head_q).is_empty():
		return -1.0
	var from := origin + Vector3.UP * 1.55 + dir * 0.25
	var to := origin + dir * 1.15 + Vector3.UP * 0.15
	var top_q := PhysicsRayQueryParameters3D.create(from, to)
	top_q.collision_mask = WORLD_MASK
	top_q.exclude = [pawn.get_rid()]
	var top := space.intersect_ray(top_q)
	if not top.has("normal") or not top.has("position"):
		return -1.0
	if (top.normal as Vector3).dot(Vector3.UP) < 0.7:
		return -1.0
	var climb := (top.position as Vector3).y - origin.y
	if climb < JUMP_CLEAR_MIN or climb > JUMP_CLEAR_MAX:
		return -1.0
	return climb


func _try_jump_ledge(wish: Vector3) -> bool:
	if pawn == null or not pawn.is_on_floor():
		return false
	if _ledge_climb(wish) < 0.0:
		return false
	pawn.velocity.y = Player.JUMP_SPEED
	return true


func _steer_to(dest: Vector3, speed: float, delta: float, use_nav: bool = true) -> void:
	var dir := Vector3.ZERO
	if use_nav and agent and not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		dir = next - pawn.global_position
		dir.y = 0.0
	# Also when the next path point is (nearly) straight above us (navmesh a bit higher than the feet, e.g.
	# beside a low ledge): the agent never reaches it and the bot would stand still forever.
	if dir.length() < 0.12:
		dir = dest - pawn.global_position
		dir.y = 0.0
	var wish := Vector3.ZERO
	if dir.length() >= 0.12:
		wish = dir.normalized()
	if _unstick_left > 0.0:
		wish = _unstick_dir
	_wants_move = wish.length_squared() > 0.0001
	var push := _separation() * 1.2
	if push.length_squared() > 0.0001:
		wish += push
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
	var on_floor := pawn.is_on_floor()
	var horiz := Vector3(pawn.velocity.x, 0.0, pawn.velocity.z)
	if on_floor:
		horiz = pawn._friction(horiz, delta)
		horiz = pawn._accelerate(horiz, wish, speed * pawn.gun_speed_mult(), Player.GROUND_ACCEL, delta)
	else:
		horiz = pawn._accelerate(horiz, wish, Player.WALK_SPEED, Player.BOT_AIR_ACCEL, delta)
	pawn.velocity.x = horiz.x
	pawn.velocity.z = horiz.z
	# Requested sprint, not the speed we have yet: the pose and the spread follow the
	# intent. Fight passes STRAFE_SPEED, so a strafe does not count as sprinting.
	pawn.is_sprinting = on_floor and _wants_move and speed >= Player.SPRINT_SPEED - 0.05
	if on_floor and _wants_move:
		_try_jump_ledge(wish)


## Turn toward _aim_track (see _tick_aim_wobble). Call _tick_aim_wobble first in the same tick.
func _face(_enemy: Player) -> void:
	var look := _aim_track
	look.y = pawn.global_position.y
	if look.distance_squared_to(pawn.global_position) > 0.04:
		pawn.look_at(look, Vector3.UP)
		pawn._yaw = pawn.rotation.y
	var aim := _aim_track - pawn.head.global_position
	if aim.length_squared() < 0.0001:
		return
	aim = aim.normalized()
	# Positive pitch looks up (same as the mouse). This was negated, so bots aimed mirrored:
	# above anyone lower than their eyes, which is everyone, and crouchers most of all.
	pawn._pitch = clampf(asin(clampf(aim.y, -1.0, 1.0)), -Player.MAX_PITCH, Player.MAX_PITCH)
	pawn.head.rotation.x = pawn._pitch


## Body follows the path. Pitch stays level; the gun comes up only once they are in the fight.
func _face_travel(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		return
	pawn.look_at(pawn.global_position + dir, Vector3.UP)
	pawn._yaw = pawn.rotation.y
	pawn._pitch = 0.0
	pawn.head.rotation.x = 0.0


## New random offset every AIM_WOBBLE_REPICK s, eased in so the crosshair drifts like a hand.
## The offset lies in the plane facing the bot (sideways and up/down), in metres at the target.
func _tick_aim_wobble(enemy: Player, delta: float) -> void:
	var fresh: bool = _aim_for != enemy
	if fresh:
		_aim_for = enemy
		_aim_err_t = 0.0
	_aim_err_t -= delta
	if _aim_err_t <= 0.0:
		_aim_err_t = AIM_WOBBLE_REPICK
		var dist := pawn.global_position.distance_to(enemy.global_position)
		var r := (AIM_WOBBLE_BASE + AIM_WOBBLE_PER_M * dist + AIM_WOBBLE_PER_SPEED * enemy._obs_speed) * float(Game.bot_profile().wobble)
		var bd := _def()
		if bd != null:
			r *= bd.bot_aim_wobble_scale
		if fresh:
			r *= AIM_WOBBLE_FRESH
		var ang := randf() * TAU
		var mag := r * sqrt(randf())
		_aim_err_goal = Vector2(cos(ang) * mag, sin(ang) * mag * 0.7)
		if fresh:
			_aim_err = _aim_err_goal
	_aim_err = _aim_err.lerp(_aim_err_goal, 1.0 - exp(-8.0 * delta))
	var base := _seen_point if _seen_target == enemy else enemy.aim_point()
	var right := (base - pawn.head.global_position).cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	# Aim where the target really is (crouch lowers it), not at a fixed standing height.
	# The crosshair follows the target a beat late: a fast strafe is harder to hit than standing still.
	var goal := base + right * _aim_err.x + Vector3.UP * _aim_err.y
	var bd := _def()
	var track := float(Game.bot_profile().track) * (bd.bot_aim_track_scale if bd != null else 1.0)
	_aim_track = goal if fresh else _aim_track.lerp(goal, 1.0 - exp(-track * delta))


## The held gun, or null before a bot has one. Every per-gun number comes from here.
func _def() -> WeaponDef:
	return pawn.weapon.def if pawn and pawn.weapon else null


## The held gun decides the fight distance (WeaponDef.bot_fight_range). Sniper holds range, the
## shotgun closes in, the LMG holds a lane — all of that now lives in the .tres.
func _fight_range() -> float:
	var d := _def()
	return d.bot_fight_range if d != null else NO_GUN_FIGHT


func _try_shoot(enemy: Player) -> void:
	if pawn.weapon == null:
		return
	if _burst_left <= 0:
		if _burst_pause > 0.0:
			return
		pawn.weapon.burst_seq += 1 # a new trigger pull (SPRAY TRANSFER)
		var bd: WeaponDef = pawn.weapon.def
		if bd == null:
			return
		_burst_left = randi_range(bd.bot_burst_min, bd.bot_burst_max)
		_burst_pause = randf_range(bd.bot_burst_pause_min, bd.bot_burst_pause_max)
		_burst_pause *= float(Game.bot_profile().pause)
	if pawn.weapon.bot_try_fire():
		_burst_left -= 1


## World (1) + players (2). Teammates are see-through (shots pass them too); other enemies still block.
## Body centre first, then the head (peeking over cover). The point that is clear becomes the aim point.
##
## #272: the answer is cached for `los_ttl` physics ticks. `_pick_target()` probes every enemy it meets
## and then `_fight()`/`_hunt()` ask again for the one they got, and the `fighting` test below asks
## every tick for the same pawn. `los_cache = false` is the old per-call behaviour, so the same build
## can be measured both ways.
func _can_see(enemy: Player, fresh: bool = false) -> bool:
	if los_cache and not fresh:
		var frame := Engine.get_physics_frames()
		var known: Dictionary = _los.get(enemy.get_instance_id(), {})
		if not known.is_empty() and frame - int(known["frame"]) < los_ttl:
			var vis: bool = known["vis"]
			if vis:
				_seen_target = enemy
				_seen_point = known["point"] as Vector3
			return vis
	var from := pawn.head.global_position
	var space := pawn.get_world_3d().direct_space_state
	var seen := false
	var at := Vector3.ZERO
	for to in [enemy.aim_point(), enemy.head_point()]:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = SHOT_MASK
		query.exclude = Game.shot_exclude(pawn)
		if count_rays:
			los_rays += 1
		var hit := space.intersect_ray(query)
		if hit.has("collider") and hit.collider == enemy:
			seen = true
			at = to
			break
	if seen:
		_seen_target = enemy
		_seen_point = at
		_remember(enemy, enemy.global_position)
	if los_cache:
		if _los.size() > LOS_CACHE_MAX:
			_los.clear() # freed pawns leave entries behind; nothing here is worth an unbounded map
		_los[enemy.get_instance_id()] = {
			"vis": seen, "point": at, "frame": Engine.get_physics_frames(),
		}
	return seen


func _enemies_by_distance() -> Array[Player]:
	var out: Array[Player] = []
	for p in Game.players(): # #272
		if p == pawn or p.is_dead or p.is_queued_for_deletion():
			continue
		if not Game.is_enemy(p, pawn):
			continue
		out.append(p)
	var here := pawn.global_position
	out.sort_custom(func(a: Player, b: Player) -> bool:
		return here.distance_squared_to(a.global_position) < here.distance_squared_to(b.global_position)
	)
	return out
