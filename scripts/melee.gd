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
const SHANK_CONE_DEG := 28.0
const SHANK_CLOSE_CONE_DEG := 50.0
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
func lunge_distance(p: Player, look_dir: Vector3) -> float:
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
	if shank:
		lunge = lunge_distance(p, dir)
		# The body moves on the machine that simulates it. A remote human's server copy does not.
		if lunge > 0.05 and (p.is_local() or p.is_bot):
			p.start_lunge(dir, lunge)
	if Game.is_networked() and not multiplayer.is_server():
		request_melee.rpc_id(1, origin, dir)
		return true
	var eye := origin
	var reach := RANGE
	if shank:
		eye = origin + _flat(dir) * lunge
		reach = SHANK_RANGE
	var res := resolve(p, eye, dir, reach, DAMAGE, shank)
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
	var reach := RANGE + SERVER_SLACK
	if shank:
		var lunge := lunge_distance(p, look_dir)
		eye = eye + _flat(look_dir) * lunge
		reach = SHANK_RANGE + SHANK_SLACK
	var res := resolve(p, eye, look_dir, reach, DAMAGE, shank)
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
func resolve(attacker: Player, origin: Vector3, look_dir: Vector3, reach: float, damage: float = DAMAGE, shank: bool = false) -> Dictionary:
	var out := {"hit": false, "killed": false}
	if not Game._is_match_authority() or look_dir.length_squared() < 0.0001:
		return out
	var dir := look_dir.normalized()
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
		var pt := Geometry3D.get_closest_point_to_segment(origin, feet, v.head_point())
		var to := pt - origin
		var d := to.length() - BODY_R
		if d > reach or d >= best_d:
			continue
		var cone := cone_near if to.length() < CLOSE else cone_far
		if to.length() > 0.05 and rad_to_deg(dir.angle_to(to)) > cone:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, pt)
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
		hit_damage = shank_damage_for(-best.global_transform.basis.z, origin - best.global_position)
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
