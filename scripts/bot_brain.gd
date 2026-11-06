class_name BotBrain
extends RefCounted
## Server-only AI. Same Player movement helpers. Gun choice changes fight distance.

const ACQUIRE := 0.28
const TOO_CLOSE := 4.0
## Only used before a bot has a weapon in hand (a gun's own fight range lives in its .tres).
const NO_GUN_FIGHT := 13.0
const STRAFE_SPEED := 6.2
## One committed sidestep, then a short pause. Re-picking every half second is what made them shimmy.
const STRAFE_HOLD_MIN := 1.3
const STRAFE_HOLD_MAX := 2.2
const STRAFE_PAUSE_MIN := 0.30
const STRAFE_PAUSE_MAX := 0.55
const STRAFE_PROBE := 1.2 # metres of open space a new sidestep needs
const STRAFE_KEEP := 0.9 # while committed: stop at a wall or a ledge, ignore a crate further out
const STRAFE_FLOOR := 2.0 # down-ray; a miss is a ledge
const MAX_STEP_SLOPE := 46.0 # same cap as the navmesh bake
const SHOT_MASK := 1 | 2
const WORLD_MASK := 1 # arena only; pawns are layer 2 and do not block each other
const MELEE_R := 1.8 # enemy this close (feet to feet) gets bashed instead of shot
const RETARGET := 0.25 # seconds between target picks (each pick costs up to 5 rays)
const SEPARATION_R := 1.3 # push away from any pawn closer than this
const STUCK_CHECK := 1.0
const STUCK_DIST := 0.4
const UNSTICK_TIME := 0.6
const HUNT_REPATH := 0.9 # seconds a hunt path is kept before asking again
const HUNT_SHIFT := 8.0 # enemy moved this far: the old path is about the wrong place
## #150: who just shot us wins over a closer stranger, for a few seconds.
const THREAT_TIME := 3.0
## A hit below this HP is a break-off, not a stand-and-trade. Short on purpose: they
## sprint away and come back from the other side, they do not camp the corner.
const RETREAT_HP := 40.0
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
const BOT_SLIDE_NEAR := 12.0 # m: closest-to-furthest band where sliding into a fight makes sense
const BOT_SLIDE_FAR := 4.5
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
var _in_fight := false
var _flank_base := 0.0 # peer slot on the ring; restored when the target changes
var _flank_angle := 0.0 # radians around the enemy; hunt aims here before closing
var _flank_flipped := false # first stuck tries the other side before a direct chase
var _hunt_direct := false # flank point was useless; path to the enemy's feet
var _path_live := false # a target has been handed to the agent this chase
var _path_enemy := Vector3.ZERO # where the enemy stood when that path was built
var _force_repath := false
## Grenades: frags at mid range, a cooldown so they do not spam.
const NADE_MIN := 7.0
const NADE_MAX := 21.0
const NADE_COOLDOWN_MIN := 7.0
const NADE_COOLDOWN_MAX := 14.0
const NADE_CHANCE := 0.35 # per fight check (every NADE_CHECK), when the range is right
const NADE_CHECK := 0.6
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


func setup(p: Player, nav: NavigationAgent3D) -> void:
	pawn = p
	agent = nav
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
	pawn.is_sprinting = false
	_retreat_cd = maxf(_retreat_cd - delta, 0.0)
	_threat_left = maxf(_threat_left - delta, 0.0)
	_hurt_retreat_left = maxf(_hurt_retreat_left - delta, 0.0)
	if _threat_left <= 0.0:
		_threat = null
	if pawn.is_dead:
		pawn.velocity = Vector3.ZERO
		return
	if Game.play_locked():
		pawn.velocity.x = 0.0
		pawn.velocity.z = 0.0
		if not pawn.is_on_floor():
			pawn.velocity.y += float(pawn.get_gravity().y) * delta
		pawn.move_and_slide()
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
		_in_fight = false
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
	var goal := CTF.bot_goal(Game, pawn) # #160: Vector3.INF outside CTF
	if enemy == null or (goal != Vector3.INF and not _can_see(enemy)):
		_in_fight = false
		_acquire_left = float(Game.bot_profile().acquire)
		if _stuck_pulse:
			_pick_unstick()
		if goal != Vector3.INF:
			_go_to_objective(goal, delta)
		else:
			_steer_to(_home, Player.WALK_SPEED, delta)
		_move(delta)
		return
	# Seen but out of weapon range (a shotgun bot at a window, the enemy across the street): sprint the
	# navmesh toward him instead of pushing straight at him into the wall.
	var out_of_range := pawn.global_position.distance_to(enemy.global_position) > _fight_range() + 4.0
	var fighting := _can_see(enemy) and not out_of_range
	if fighting:
		if not _in_fight:
			# A fresh fight probes a sidestep. The hunt path is dropped so the next
			# approach starts from a flank point again.
			_strafe_hold = 0.0
			_strafe_pause = 0.0
			_unstick_left = 0.0
			_hunt_direct = false
			_path_live = false
		_in_fight = true
		_acquire_left = maxf(_acquire_left - delta, 0.0)
		_fight(enemy, delta)
	else:
		_in_fight = false
		_acquire_left = float(Game.bot_profile().acquire)
		_hunt(enemy, delta)
	_move(delta)


## move_and_slide plus the same small step-up the players get (StepUp), so bots do not stall on a lip.
## Before it moves: slide, wallrun and dive, through the very same Movement code a human runs.
func _move(delta: float) -> void:
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
	_crouch_hold = maxf(_crouch_hold - delta, 0.0)
	var on_floor := pawn.is_on_floor()
	var foe := _target
	var has_foe := foe != null and is_instance_valid(foe) and not foe.is_dead
	# A slide to close the last stretch of a fight, on the floor, moving fast, off cooldown.
	if on_floor and has_foe and _in_fight and not pawn._sliding and _crouch_hold <= 0.0 and pawn._slide_cd <= 0.0:
		var dist := pawn.global_position.distance_to(foe.global_position)
		var fast := Vector2(pawn.velocity.x, pawn.velocity.z).length() >= Player.WALK_SPEED * 1.05
		if fast and dist > BOT_SLIDE_FAR and dist < BOT_SLIDE_NEAR:
			_crouch_press = true
			_crouch_hold = BOT_SLIDE_HOLD
	# A dive when it is falling toward a target: closes the gap, and it lands into a roll.
	elif not on_floor and has_foe and pawn._dive_cd <= 0.0 and pawn.velocity.y < -1.0:
		if pawn.global_position.distance_to(foe.global_position) < BOT_DIVE_RANGE:
			_crouch_press = true
			_crouch_hold = maxf(_crouch_hold, 0.2)
	_set_bot_input()
	Movement.try_start_slide(pawn, on_floor, false)
	Movement.try_air_dive(pawn, on_floor, false)
	# Forward is the travel direction (the brain faces it), so "forward held" is what walls want.
	Movement.tick_wallrun(pawn, delta, Vector2(0.0, -1.0), false)
	if pawn._wallrunning:
		var horiz := Vector3(pawn.velocity.x, 0.0, pawn.velocity.z)
		var along := horiz.normalized() if horiz.length_squared() > 0.01 else -pawn.transform.basis.z
		var h := Movement.wallrun_horiz(pawn, horiz, along, delta)
		pawn.velocity.x = h.x
		pawn.velocity.z = h.z
	if pawn._sliding:
		# Keep the slide on its own line at sprint speed; finish_slide decides when it is over.
		var dir := pawn._slide_dir
		var sp := maxf(Vector2(pawn.velocity.x, pawn.velocity.z).length(), Player.SPRINT_SPEED)
		pawn.velocity.x = dir.x * sp
		pawn.velocity.z = dir.z * sp
	Movement.finish_slide(pawn)
	# The same stance code the human runs: crouch follows the held key, and releases when the slide,
	# the dive or the roll is over.
	pawn._update_stance(delta, on_floor)


## Nearest enemy we can actually see; else the nearest one to hunt. Re-picked every RETARGET.
## Closest-only used to lock bots onto someone hidden behind a teammate (issue #1: the pile in the middle).
func _pick_target(delta: float) -> Player:
	_retarget_t -= delta
	if _retarget_t > 0.0 and _valid_target(_target):
		# Still look now when the pawn who shot us is in sight and not the current target.
		if not (_valid_target(_threat) and _target != _threat and _can_see(_threat)):
			return _target
	_retarget_t = RETARGET
	var enemies := _enemies_by_distance()
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
	if _target == null and _valid_target(_threat):
		_target = _threat # hunt the one who shot, not whoever is nearest through a wall
	elif _target == null and not enemies.is_empty():
		_target = enemies[0]
	if _target != prev:
		_hunt_direct = false
		_flank_flipped = false
		_flank_angle = _flank_base
		_path_live = false
		_force_repath = true
		_repath_t = 0.0
	return _target


## #150: a hit from another pawn. Prefer them as the target, and break off the trade when low.
func note_threat(attacker: Player) -> void:
	if not _valid_target(attacker):
		return
	_threat = attacker
	_threat_left = THREAT_TIME
	_retarget_t = 0.0
	if Game.hp_of(pawn) <= RETREAT_HP and _retreat_cd <= 0.0:
		_hurt_retreat_left = RETREAT_TIME
		_retreat_cd = RETREAT_CD
		_flank_angle += PI
		_flank_flipped = true
		_hunt_direct = false
		_path_live = false
		_force_repath = true
		_in_fight = false


## Untyped on purpose: a freed pawn in a typed Player argument is a runtime error.
func _valid_target(p) -> bool:
	return (
		is_instance_valid(p)
		and not p.is_queued_for_deletion()
		and not p.is_dead
		and (p.team_id != pawn.team_id or Game.is_ffa())
		and p != pawn
	)


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
	for n in pawn.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p == pawn or p.is_dead:
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


## No line of sight, or seen but outside gun range. Follow the navmesh.
## First to a point beside the enemy (different bots, different doors), then to their feet.
func _hunt(enemy: Player, delta: float) -> void:
	if not _path_live:
		_force_repath = true
	if _stuck_pulse:
		_on_hunt_stuck()
	# is_navigation_finished is still true the frame a target is set; the path arrives after.
	var followed := _path_live and _repath_t < HUNT_REPATH - 0.2
	if followed and not _hunt_direct and agent and agent.is_navigation_finished():
		_hunt_direct = true
		_force_repath = true
	var shifted := (
		_path_live
		and _path_enemy.distance_squared_to(enemy.global_position) > HUNT_SHIFT * HUNT_SHIFT
	)
	_repath_t -= delta
	# Keep the enemy's height. Snapping to our own y picks the floor under a roof, so the
	# path never takes the ramp when someone is standing up there. Steering still ignores y.
	var dest := enemy.global_position if _hunt_direct else _flank_point(enemy)
	if agent and (_repath_t <= 0.0 or shifted or _force_repath):
		agent.target_position = dest
		_path_enemy = enemy.global_position
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


## Visible and in range. Sidestep in the open; do not ask the navmesh for a 2 m shuffle.
func _fight(enemy: Player, delta: float) -> void:
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
	var fight_r := _fight_range()
	var wish := Vector3.ZERO
	if _strafe_pause > 0.0:
		_strafe_pause = maxf(_strafe_pause - delta, 0.0)
		# Almost still: only a step when the range is wrong, so the player gets a shot.
		if dist < TOO_CLOSE:
			wish = away
		elif dist > fight_r:
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
			if dist < TOO_CLOSE:
				wish += away * 0.7
			elif dist > fight_r:
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


## Frag at a visible enemy in mid range. The pitch is solved so the arc lands near them before the fuse.
func _try_grenade(enemy: Player, dist: float, delta: float) -> bool:
	_nade_check -= delta
	if _nade_cd > 0.0 or pawn.grenades <= 0 or _nade_check > 0.0:
		return false
	_nade_check = NADE_CHECK
	if dist < NADE_MIN or dist > NADE_MAX or randf() > NADE_CHANCE:
		return false
	var from := pawn.head.global_position
	var to := enemy.global_position + Vector3(0.0, 0.4, 0.0)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var d := flat.length()
	if d < 0.5:
		return false
	var dy := to.y - from.y
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var best := INF
	var best_pitch := 0.0
	for k in 25:
		var pitch := lerpf(-0.35, 0.9, float(k) / 24.0)
		var h := Grenade.THROW_SPEED * cos(pitch)
		var t := d / h
		if t > Grenade.FUSE + 0.15:
			continue
		var vy := Grenade.THROW_SPEED * sin(pitch) + 4.0
		var err := absf(vy * t - 0.5 * g * t * t - dy)
		if err < best:
			best = err
			best_pitch = pitch
	if best > 2.0:
		return false
	var dir := flat.normalized() * cos(best_pitch) + Vector3.UP * sin(best_pitch)
	dir = (dir + Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04))).normalized()
	_nade_cd = randf_range(NADE_COOLDOWN_MIN, NADE_COOLDOWN_MAX) * float(Game.bot_profile().nade)
	Game.throw_grenade(pawn, from + dir * 0.6, dir)
	return true


## Banked UAV: use it after a short beat. Banked RC-XD: send it when the target is far or hidden.
func _tick_streaks(delta: float, enemy: Player) -> void:
	var charges := int(Game.streak_charges.get(pawn.peer_id, 0))
	if charges == 0:
		_streak_wait = float(Game.bot_profile().streak)
		return
	_streak_wait = maxf(_streak_wait - delta, 0.0)
	if _streak_wait > 0.0:
		return
	if (charges & Game.CHARGE_RADAR) != 0:
		Game.try_activate_streak(pawn.peer_id, 0)
		_streak_wait = float(Game.bot_profile().streak)
		return
	if (charges & Game.CHARGE_RCXD) != 0 and enemy != null:
		var far := pawn.global_position.distance_to(enemy.global_position) >= RC_LAUNCH_MIN
		if far or not _can_see(enemy):
			Game.try_activate_streak(pawn.peer_id, 1)
			_rc_repath = 0.0
			_streak_wait = float(Game.bot_profile().streak)


## While our car is out the pawn stands still (like a player in the RC view) and we steer the car
## along the navmesh to the nearest enemy, then blow it up next to them.
func _drive_rc(delta: float) -> bool:
	var car := RcXd.for_owner(pawn.peer_id)
	if car == null:
		return false
	pawn.velocity.x = 0.0
	pawn.velocity.z = 0.0
	pawn.move_and_slide()
	var here := car.global_position
	var best: Player = null
	var best_d := INF
	for n in pawn.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p == pawn or p.is_dead or not Game.is_enemy(p, pawn):
			continue
		var dd := here.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = p
	if best == null:
		car.apply_remote_input(car.yaw, 0.0)
		return true
	if best_d <= RC_BLOW_R:
		car.shutdown(true)
		return true
	_rc_repath -= delta
	if _rc_repath <= 0.0 or here.distance_to(_rc_point) < 1.2:
		_rc_repath = 0.4
		_rc_point = best.global_position
		if agent:
			var path := NavigationServer3D.map_get_path(agent.get_navigation_map(), here, best.global_position, true)
			for pt in path:
				if Vector2(pt.x - here.x, pt.z - here.z).length() > 1.5:
					_rc_point = pt
					break
	var to := _rc_point - here
	var want_yaw := atan2(-to.x, -to.z) if Vector2(to.x, to.z).length() > 0.05 else car.yaw
	var turn := absf(wrapf(want_yaw - car.yaw, -PI, PI))
	car.apply_remote_input(want_yaw, 0.55 if turn > 1.2 else 1.0)
	return true


## Point on a ring around the enemy at fight range. Y stays theirs so roofs still route up a ramp.
func _flank_point(enemy: Player) -> Vector3:
	var dest := enemy.global_position
	dest.x += cos(_flank_angle) * _fight_range()
	dest.z += sin(_flank_angle) * _fight_range()
	return dest


## Stuck on a hunt path: other side of the enemy, then straight at them, then a short nudge.
func _on_hunt_stuck() -> void:
	if not _flank_flipped and not _hunt_direct:
		_flank_angle += PI
		_flank_flipped = true
		_force_repath = true
	elif not _hunt_direct:
		_hunt_direct = true
		_force_repath = true
	else:
		_pick_unstick()
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
		_strafe_hold = randf_range(STRAFE_HOLD_MIN, STRAFE_HOLD_MAX)
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
func _can_see(enemy: Player) -> bool:
	var from := pawn.head.global_position
	var space := pawn.get_world_3d().direct_space_state
	for to in [enemy.aim_point(), enemy.head_point()]:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = SHOT_MASK
		query.exclude = Game.shot_exclude(pawn)
		var hit := space.intersect_ray(query)
		if hit.has("collider") and hit.collider == enemy:
			_seen_target = enemy
			_seen_point = to
			return true
	return false


func _enemies_by_distance() -> Array[Player]:
	var out: Array[Player] = []
	for n in pawn.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p == pawn or p.is_dead or p.is_queued_for_deletion():
			continue
		if not Game.is_enemy(p, pawn):
			continue
		out.append(p)
	var here := pawn.global_position
	out.sort_custom(func(a: Player, b: Player) -> bool:
		return here.distance_squared_to(a.global_position) < here.distance_squared_to(b.global_position)
	)
	return out
