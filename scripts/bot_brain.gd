class_name BotBrain
extends RefCounted
## Server-only AI. Same Player movement helpers. Gun choice changes fight distance.

const ACQUIRE := 0.28
const FIGHT_RANGE := 11.0
const TOO_CLOSE := 4.0
const SHOTGUN_FIGHT := 6.0
const RIFLE_FIGHT := 13.0
const PISTOL_FIGHT := 9.0
const SNIPER_FIGHT := 18.0 # keep range; one shot then a long pause
const STRAFE_SPEED := 6.2
const SHOT_MASK := 1 | 2
const MELEE_R := 1.8 # enemy this close (feet to feet) gets bashed instead of shot
const RETARGET := 0.25 # seconds between target picks (each pick costs up to 5 rays)
const SEPARATION_R := 1.3 # push away from any pawn closer than this
const STUCK_CHECK := 1.0
const STUCK_DIST := 0.4
const UNSTICK_TIME := 0.6
## Hand wobble around the aim point (metres at the target), so a correct aim is not an aimbot.
const AIM_WOBBLE_BASE := 0.85
const AIM_WOBBLE_PER_M := 0.012 # wider with distance
const AIM_WOBBLE_PER_SPEED := 0.07 # and when the target moves (per m/s)
const AIM_WOBBLE_FRESH := 1.8 # first moments on a new target
const AIM_WOBBLE_REPICK := 0.3
const AIM_TRACK := 14.0 # how fast the aim catches up with a moving target (1/s)

var pawn: Player
var agent: NavigationAgent3D
var _acquire_left := ACQUIRE
var _strafe_t := 0.0
var _strafe_sign := 1.0
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
var _unstick_left := 0.0
var _unstick_dir := Vector3.ZERO


func setup(p: Player, nav: NavigationAgent3D) -> void:
	pawn = p
	agent = nav
	_home = p.global_position
	_stuck_pos = p.global_position
	_strafe_sign = -1.0 if randf() < 0.5 else 1.0
	_burst_pause = randf_range(0.25, 0.7)


## Hunt if no LOS, strafe+shoot if visible. Shotgun bots push closer than rifle.
func physics_tick(delta: float) -> void:
	if pawn == null:
		return
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
	if not pawn.is_on_floor():
		pawn.velocity.y += float(pawn.get_gravity().y) * delta
	else:
		pawn.velocity.y = 0.0
	_track_stuck(delta)
	var enemy := _pick_target(delta)
	if enemy == null:
		_acquire_left = ACQUIRE
		_steer_to(_home, Player.WALK_SPEED, delta)
		pawn.move_and_slide()
		return
	if _can_see(enemy):
		_acquire_left = maxf(_acquire_left - delta, 0.0)
		_fight(enemy, delta)
	else:
		_acquire_left = ACQUIRE
		_hunt(enemy, delta)
	pawn.move_and_slide()


## Nearest enemy we can actually see; else the nearest one to hunt. Re-picked every RETARGET.
## Closest-only used to lock bots onto someone hidden behind a teammate (issue #1: the pile in the middle).
func _pick_target(delta: float) -> Player:
	_retarget_t -= delta
	if _retarget_t > 0.0 and _valid_target(_target):
		return _target
	_retarget_t = RETARGET
	var enemies := _enemies_by_distance()
	_target = null
	for e in enemies:
		if _can_see(e):
			_target = e
			break
	if _target == null and not enemies.is_empty():
		_target = enemies[0]
	return _target


## Untyped on purpose: a freed pawn in a typed Player argument is a runtime error.
func _valid_target(p) -> bool:
	return (
		is_instance_valid(p)
		and not p.is_queued_for_deletion()
		and not p.is_dead
		and p.team_id != pawn.team_id
	)


## No progress for STUCK_CHECK while trying to move → walk a random way for a moment.
func _track_stuck(delta: float) -> void:
	_unstick_left = maxf(_unstick_left - delta, 0.0)
	_stuck_t += delta
	if _stuck_t < STUCK_CHECK:
		return
	_stuck_t = 0.0
	var moved := pawn.global_position.distance_to(_stuck_pos)
	_stuck_pos = pawn.global_position
	if moved < STUCK_DIST and _wants_move and _unstick_left <= 0.0:
		var a := randf() * TAU
		_unstick_dir = Vector3(cos(a), 0.0, sin(a))
		_unstick_left = UNSTICK_TIME


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


func _hunt(enemy: Player, delta: float) -> void:
	_repath_t -= delta
	var dest := enemy.global_position
	dest.y = pawn.global_position.y
	if _repath_t <= 0.0 and agent:
		agent.target_position = dest
		_repath_t = 0.22
	_tick_aim_wobble(enemy, delta)
	_face(enemy)
	_steer_to(dest, Player.WALK_SPEED, delta)


func _fight(enemy: Player, delta: float) -> void:
	_tick_aim_wobble(enemy, delta)
	_face(enemy)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_sign *= -1.0
		_strafe_t = randf_range(0.55, 1.2)
	var away := pawn.global_position - enemy.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = pawn.transform.basis.z
	away = away.normalized()
	var side := Vector3.UP.cross(away).normalized() * _strafe_sign
	var dist := pawn.global_position.distance_to(enemy.global_position)
	var fight_r := _fight_range()
	var dest := pawn.global_position + side * 2.6
	if dist < TOO_CLOSE:
		dest += away * 3.4
	elif dist > fight_r:
		dest += -away * 2.8
	_repath_t -= delta
	if _repath_t <= 0.0 and agent:
		agent.target_position = dest
		_repath_t = 0.16
	_steer_to(dest, STRAFE_SPEED, delta)
	if _acquire_left <= 0.0 and dist <= MELEE_R and Game.melee.swing(pawn):
		return
	if _acquire_left <= 0.0 and dist <= fight_r + 4.0:
		_try_shoot(enemy)


func _steer_to(dest: Vector3, speed: float, delta: float) -> void:
	var dir := Vector3.ZERO
	if agent and not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		dir = next - pawn.global_position
		dir.y = 0.0
	if dir.length() < 0.08:
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
		horiz = pawn._accelerate(horiz, wish, speed, Player.GROUND_ACCEL, delta)
	else:
		horiz = pawn._accelerate(horiz, wish, Player.WALK_SPEED, Player.AIR_ACCEL, delta)
	pawn.velocity.x = horiz.x
	pawn.velocity.z = horiz.z


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
		var r := AIM_WOBBLE_BASE + AIM_WOBBLE_PER_M * dist + AIM_WOBBLE_PER_SPEED * enemy._obs_speed
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
	_aim_track = goal if fresh else _aim_track.lerp(goal, 1.0 - exp(-AIM_TRACK * delta))


func _gun_id() -> StringName:
	if pawn and pawn.weapon and pawn.weapon.def:
		return pawn.weapon.def.id
	return &"rifle"


func _fight_range() -> float:
	match _gun_id():
		&"shotgun":
			return SHOTGUN_FIGHT
		&"pistol":
			return PISTOL_FIGHT
		&"sniper":
			return SNIPER_FIGHT
		_:
			return RIFLE_FIGHT


func _try_shoot(enemy: Player) -> void:
	if pawn.weapon == null:
		return
	if _burst_left <= 0:
		if _burst_pause > 0.0:
			return
		match _gun_id():
			&"shotgun":
				_burst_left = 1
				_burst_pause = randf_range(0.55, 1.05)
			&"sniper":
				_burst_left = 1
				_burst_pause = randf_range(0.85, 1.4)
			&"pistol":
				_burst_left = randi_range(3, 6)
				_burst_pause = randf_range(0.28, 0.6)
			_:
				_burst_left = randi_range(2, 5)
				_burst_pause = randf_range(0.35, 0.85)
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
		if p.team_id == pawn.team_id:
			continue
		out.append(p)
	var here := pawn.global_position
	out.sort_custom(func(a: Player, b: Player) -> bool:
		return here.distance_squared_to(a.global_position) < here.distance_squared_to(b.global_position)
	)
	return out
