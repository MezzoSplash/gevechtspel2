class_name Melee
extends Node
## E: weapon bash. The swing (animation, sound) plays at once on the swinging machine; whether it
## hits is decided on the match authority only. Node /root/Game/Melee on every machine (RPC path).
## The shank (a melee primary) uses the same path with its own reach, cone and damage.

const DAMAGE := 50.0 # two bashes from full HP, never a headshot
const RANGE := 2.0 # metres from the eye to the target's body surface
const SERVER_SLACK := 0.5 # extra reach for a client's request: our copy of the pawns lags a little
const CONE_DEG := 40.0 # half angle around the look direction
const CLOSE_CONE_DEG := 75.0 # nose to nose the angle to the body centre gets large
const CLOSE := 0.7
const BODY_R := 0.4 # capsule radius plus a little
const COOLDOWN := 0.8
const COOLDOWN_SLACK := 0.12 # packet bunching; the client itself always waits the full COOLDOWN
const WORLD_MASK := 1
const WEAPON_ID := &"melee"

## Shank (#145). Front is the bash (two hits). The rear arc is one hit. A side is a front.
const SHANK_ID := &"shank"
const SHANK_RANGE := 2.2
## #373: the same cones as the bash. A stab is a short melee hit, not a precision tool, and with 28 deg a
## sprinting stab missed everything the player saw in front of them.
const SHANK_CONE_DEG := 40.0
const SHANK_CLOSE_CONE_DEG := 75.0
## The target may sit this far off the look direction when the lunge is planned: the step is aimed at the
## body, not at the crosshair.
const SHANK_PICK_CONE_DEG := 45.0
## The lunge stops this far in front of the target's body, so the stab lands on it instead of past it.
const LUNGE_STOP := 0.3
const SHANK_SLACK := 0.25 # less than the bash: the lunge already reaches
const FRONT_DAMAGE := 50.0
const BACK_DAMAGE := 100.0
## cos of the angle from the victim's forward to the attacker. -1 is straight behind,
## 0 is the side. At or below this the stab is a backstab; anything else, including the side, is 50.
const BACK_DOT := -0.34
const LUNGE_M := 2.5
const LUNGE_TIME := 0.16 # s. 2.5 m in that window stays under the position-claim speed cap.
const SHANK_CHASE := 6.0 # m. Bots holding the shank sprint in from here and stab.

var _last: Dictionary = {} # authority: peer_id → time (s) of the last accepted client swing


func can_swing(p: Player) -> bool:
	if p == null or p.is_dead or Game.play_locked():
		return false
	return p.weapon != null and p.camera != null


## Straight behind the victim (their feet to the stab's eye) is a kill. Side and front are not.
static func behind(victim_forward: Vector3, to_attacker: Vector3) -> bool:
	var f := Vector3(victim_forward.x, 0.0, victim_forward.z)
	var t := Vector3(to_attacker.x, 0.0, to_attacker.z)
	if f.length_squared() < 0.0001 or t.length_squared() < 0.0001:
		return false
	return f.normalized().dot(t.normalized()) <= BACK_DOT


static func shank_damage_for(victim_forward: Vector3, to_attacker: Vector3) -> float:
	return BACK_DAMAGE if behind(victim_forward, to_attacker) else FRONT_DAMAGE


## Feet on walkable floor, from a short ray: the server's copy of a remote human is never moved by
## move_and_slide, so its is_on_floor() says nothing.
static func on_ground(p: Player) -> bool:
	var space := p.get_world_3d().direct_space_state
	if space == null:
		return p.is_on_floor()
	var from := p.global_position + Vector3.UP * 0.2
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.45)
	q.collision_mask = WORLD_MASK
	q.exclude = [p.get_rid()]
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit.normal as Vector3).y >= 0.7


static func _flat(dir: Vector3) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()


## How far a sprinting pawn can lunge along `look_dir` before a wall. 0 when they are not at sprint,
## when they are off the ground, or when they already move faster than the lunge: the lunge sets the
## horizontal velocity, so a stab mid-surf, mid-grapple or mid-carry would brake the run and bend its
## line, and in the air it would be a free air-dash. Those stabs keep plain SHANK_RANGE reach.
static func lunge_distance(p: Player, look_dir: Vector3) -> float:
	if p == null or not p.at_sprint():
		return 0.0
	if p.flat_speed() >= LUNGE_M / LUNGE_TIME:
		return 0.0
	if not on_ground(p):
		return 0.0
	var flat := _flat(look_dir)
	if flat == Vector3.ZERO:
		return 0.0
	var from := p.global_position + Vector3(0.0, 0.8, 0.0)
	var to := from + flat * LUNGE_M
	var space := p.get_world_3d().direct_space_state
	if space == null:
		return LUNGE_M
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = WORLD_MASK
	query.exclude = [p.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return LUNGE_M
	return maxf(from.distance_to(hit.position) - 0.35, 0.0)


## #373/#384: the enemy a lunge is aimed at. Chosen before the lunge, in a wider cone than the hit
## itself, with no wall in between, so the step can stop right in front of that body instead of
## running past it. The shank stabs from the eye, the LOS hands lunge from wherever they fly; both
## share this picker so a fix to one is a fix to the other.
static func pick_target(origin: Vector3, look_dir: Vector3, me: Player, max_m: float, cone_deg: float,
		skip: Array = []) -> Player:
	var dir := _flat(look_dir)
	if me == null or dir == Vector3.ZERO or not me.is_inside_tree():
		return null
	var space := me.get_world_3d().direct_space_state
	var best: Player = null
	var best_d := INF
	for n in me.get_tree().get_nodes_in_group("player"):
		var v := n as Player
		if v == null or v == me or v.is_dead or v.is_queued_for_deletion():
			continue
		if not Game.is_enemy(v, me):
			continue
		var to := _flat(v.global_position - origin)
		if to.length_squared() < 0.0025:
			continue
		# #384: the reach is the real 3D distance to the body, not the horizontal gap: hands flying
		# three metres above a target used to read as "0.5 m away" and then lunge straight over it.
		# The cone stays horizontal, so the shank on the ground behaves exactly as before.
		var d := origin.distance_to(v.global_position + Vector3(0.0, 1.0, 0.0))
		if d > max_m or d >= best_d:
			continue
		if rad_to_deg(dir.angle_to(to)) > cone_deg:
			continue
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(origin, v.global_position + Vector3(0, 1.0, 0))
			q.collision_mask = WORLD_MASK
			q.exclude = [me.get_rid()] + skip
			if not space.intersect_ray(q).is_empty():
				continue
		best = v
		best_d = d
	return best


static func shank_target(p: Player, look_dir: Vector3) -> Player:
	if p == null:
		return null
	return pick_target(p.global_position + Vector3(0.0, 1.4, 0.0), look_dir, p,
		LUNGE_M + SHANK_RANGE, SHANK_PICK_CONE_DEG)


## Where the step goes: straight at the target, stopping just in front of its body, and never through a
## wall and never further than LUNGE_M. Without a target it is the plain step along the look direction.
## Returns [direction, distance]; the direction is flat.
static func shank_step(p: Player, look_dir: Vector3, target: Player) -> Array:
	var dir := _flat(look_dir)
	if dir == Vector3.ZERO:
		return [dir, 0.0]
	if target != null and is_instance_valid(target) and not target.is_dead:
		var to := _flat(target.global_position - p.global_position)
		if to != Vector3.ZERO:
			dir = to
	var room := lunge_distance(p, dir) # 0 when not sprinting on the ground: no step, no reach stretch
	if room <= 0.0:
		return [dir, 0.0]
	if target != null and is_instance_valid(target):
		var gap := maxf(p.global_position.distance_to(target.global_position) - BODY_R - LUNGE_STOP, 0.0)
		room = minf(room, minf(gap, LUNGE_M))
	return [dir, room]


## Local human or a bot on the authority. Returns false when the swing is not ready.
func swing(p: Player) -> bool:
	return _swing(p, false)


## The shank primary. Same cooldown and swing as the bash, other reach and damage.
func swing_shank(p: Player) -> bool:
	if p == null or p.weapon == null or p.weapon.def == null or not p.weapon.def.melee:
		return false
	return _swing(p, true)


func _swing(p: Player, shank: bool) -> bool:
	if not can_swing(p) or not p.weapon.melee_ready():
		return false
	p.weapon.play_melee()
	var origin := p.camera.global_position
	var dir := -p.camera.global_transform.basis.z
	var lunge := 0.0
	var aim := dir
	# #388: Overdrive lends the shank's step to whatever is in your hands; the reach stays the weapon's.
	var steps := shank or Overdrive.lunges(p)
	if steps:
		# #373: pick the body first, then step to it. The step used to run the full 2.5 m past anything
		# closer than that, so the stab started behind the target and missed.
		var plan := shank_step(p, dir, shank_target(p, dir))
		aim = plan[0]
		lunge = float(plan[1])
		if lunge > 0.05 and (p.is_local() or p.is_bot):
			p.start_lunge(aim, lunge)
	if Game.is_networked() and not multiplayer.is_server():
		request_melee.rpc_id(1, origin, dir)
		return true
	var reach := RANGE
	var path_end := Vector3.INF
	if steps:
		# #373 review: the step runs from the eye where the stab starts to where the lunge ends. Passing the
		# end as both ends made the "whole path" a point, so a body that moved off the planned spot (a
		# server copy that is newer than what the client aimed at) was judged from the end only.
		path_end = origin + _flat(aim) * lunge
		if shank:
			reach = SHANK_RANGE
		dir = aim
	var res := resolve(p, origin, dir, reach, DAMAGE, shank, path_end)
	_report(p, res)
	return true


func _report(p: Player, res: Dictionary) -> void:
	if res.hit:
		p.weapon.play_melee_hit()
		if p.is_local():
			Game.hit_confirmed.emit(res.killed, false)
			p.weapon.play_hit_feedback(res.killed, false)
	if Game.is_networked():
		sync_melee.rpc(p.peer_id, res.hit)


## Client → server. Checks: alive, not frozen / killcam, cooldown, and an eye near our copy of it.
## The hit itself is found here with the server's pawns, from the server's copy of the eye.
## A shank lunges that eye forward when the pawn is already at sprint speed. The body lunge
## stays on the client: position claims carry it, this does not teleport the server pawn.
@rpc("any_peer", "reliable")
func request_melee(origin: Vector3, look_dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var p := Game.player_for_peer(peer)
	if p == null or p.is_bot or not can_swing(p):
		return
	if look_dir.length_squared() < 0.0001 or not Game.origin_plausible(p, origin):
		return
	if not _take_cooldown(peer):
		return
	var shank := p.weapon.def != null and p.weapon.def.melee
	# Reach is measured from our copy of the eye, so the 4 m origin tolerance cannot stretch it.
	var eye := p.camera.global_position
	var start := eye
	var reach := RANGE + SERVER_SLACK
	var aim := look_dir
	var stepped := shank or Overdrive.lunges(p)
	if stepped:
		# #373: the same target and the same step as the client, from our own copy of the pawns, so the
		# server does not judge a stab at a body the step already went past.
		var plan := shank_step(p, look_dir, shank_target(p, look_dir))
		aim = plan[0]
		eye = eye + _flat(aim) * float(plan[1])
		if shank:
			reach = SHANK_RANGE + SHANK_SLACK
	var res := resolve(p, start, aim, reach, DAMAGE, shank, eye if stepped else Vector3.INF)
	if not Game.is_dedicated:
		p.weapon.play_melee()
		if res.hit:
			p.weapon.play_melee_hit()
	sync_melee.rpc(peer, res.hit)
	if res.hit:
		Game.notify_hit.rpc_id(peer, res.killed, false)


## Everyone else sees the swing; the swinger only gets the thud once the server says it landed.
@rpc("authority", "reliable")
func sync_melee(peer_id: int, hit: bool) -> void:
	if multiplayer.is_server():
		return
	var p := Game.player_for_peer(peer_id)
	if p == null or p.weapon == null:
		return
	if not p.is_local():
		p.weapon.play_melee()
	if hit:
		p.weapon.play_melee_hit()


func _take_cooldown(peer: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if _last.has(peer) and now - float(_last[peer]) < COOLDOWN - COOLDOWN_SLACK:
		return false
	_last[peer] = now
	return true


## Authority only. Nearest living enemy whose body is within `reach` of the eye, inside the cone,
## with no wall in between. Damage goes through Player.apply_hit, so kills, the kill feed,
## streaks, and the killcam work as for guns.
## `damage` is normally DAMAGE; the LOS hands pass a lethal number, which is that streak's payoff.
## `shank` picks 100 or 50 from where the eye sits relative to the victim's back, and tags the kill
## as "shank" so Gun Game still demotes.
## `path_end` (#373): where the stab's eye is after a lunge. The hit is tested against the whole step from
## the eye to that point, so a body the lunge passes through is still a hit; without it the test is the
## single point it always was.
func resolve(attacker: Player, origin: Vector3, look_dir: Vector3, reach: float, damage: float = DAMAGE, shank: bool = false, path_end: Vector3 = Vector3.INF) -> Dictionary:
	var out := {"hit": false, "killed": false}
	if not Game._is_match_authority() or look_dir.length_squared() < 0.0001:
		return out
	var dir := look_dir.normalized()
	var end := origin if path_end == Vector3.INF else path_end
	var space := attacker.get_world_3d().direct_space_state
	var best: Player = null
	var best_d := INF
	var best_pt := Vector3.ZERO
	var cone_far := SHANK_CONE_DEG if shank else CONE_DEG
	var cone_near := SHANK_CLOSE_CONE_DEG if shank else CLOSE_CONE_DEG
	for n in get_tree().get_nodes_in_group("player"):
		var v := n as Player
		if v == null or v == attacker or v.is_dead or v.is_queued_for_deletion():
			continue
		if not Game.is_enemy(v, attacker):
			continue
		var feet := v.global_position + Vector3(0, 0.25, 0)
		var pair := Geometry3D.get_closest_points_between_segments(origin, end, feet, v.head_point())
		var near: Vector3 = pair[0]
		var pt: Vector3 = pair[1]
		var to := pt - near
		var d := to.length() - BODY_R
		if d > reach or d >= best_d:
			continue
		var cone := cone_near if to.length() < CLOSE else cone_far
		# #373 review: a step that runs through the body (closer than its radius) hits whatever the angle;
		# the line from the path to the body's axis is then near vertical and failed the cone. Bash unchanged.
		var inside := BODY_R if shank and end != origin else 0.05
		if to.length() > inside and rad_to_deg(dir.angle_to(to)) > cone:
			continue
		var query := PhysicsRayQueryParameters3D.create(near, pt)
		query.collision_mask = WORLD_MASK
		if not space.intersect_ray(query).is_empty():
			continue
		best = v
		best_d = d
		best_pt = pt
	if best == null:
		return out
	var killer_id := attacker.peer_id
	if killer_id <= 0:
		killer_id = attacker._owner_peer()
	var hit_damage := damage
	var weapon_id := WEAPON_ID
	if shank:
		weapon_id = SHANK_ID
		hit_damage = shank_damage_for(-best.global_transform.basis.z, end - best.global_position)
	Game.begin_melee_ctx(attacker, origin) # SURF / DROP KILL use the swing. During LOS that origin is the hands, not the eye.
	var r := best.apply_hit(best_pt, -dir, hit_damage, false, killer_id, weapon_id, 1.0, attacker.global_position)
	Game.end_melee_ctx()
	out.hit = int(r.get("damage", 0)) > 0
	out.killed = bool(r.get("killed", false))
	return out


func forget(peer_id: int) -> void:
	_last.erase(peer_id)


func reset() -> void:
	_last.clear()
