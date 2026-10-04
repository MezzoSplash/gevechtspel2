class_name Melee
extends Node
## E: weapon bash. The swing (animation, sound) plays at once on the swinging machine; whether it
## hits is decided on the match authority only. Node /root/Game/Melee on every machine (RPC path).

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

var _last: Dictionary = {} # authority: peer_id → time (s) of the last accepted client swing


func can_swing(p: Player) -> bool:
	if p == null or p.is_dead or Game.play_locked():
		return false
	return p.weapon != null and p.camera != null


## Local human or a bot on the authority. Returns false when the swing is not ready.
func swing(p: Player) -> bool:
	if not can_swing(p) or not p.weapon.melee_ready():
		return false
	p.weapon.play_melee()
	var origin := p.camera.global_position
	var dir := -p.camera.global_transform.basis.z
	if Game.is_networked() and not multiplayer.is_server():
		request_melee.rpc_id(1, origin, dir)
		return true
	var res := resolve(p, origin, dir, RANGE)
	if res.hit:
		p.weapon.play_melee_hit()
		if p.is_local():
			Game.hit_confirmed.emit(res.killed, false)
			p.weapon.play_hit_feedback(res.killed, false)
	if Game.is_networked():
		sync_melee.rpc(p.peer_id, res.hit)
	return true


## Client → server. Checks: alive, not frozen / killcam, cooldown, and an eye near our copy of it.
## The hit itself is found here with the server's pawns, from the server's copy of the eye.
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
	# Reach is measured from our copy of the eye, so the 4 m origin tolerance cannot stretch it.
	var res := resolve(p, p.camera.global_position, look_dir, RANGE + SERVER_SLACK)
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
## with no wall in between. Damage goes through Player.apply_hit, so kills, the kill feed
## (weapon "melee"), streaks, and the killcam work as for guns.
func resolve(attacker: Player, origin: Vector3, look_dir: Vector3, reach: float) -> Dictionary:
	var out := {"hit": false, "killed": false}
	if not Game._is_match_authority() or look_dir.length_squared() < 0.0001:
		return out
	var dir := look_dir.normalized()
	var space := attacker.get_world_3d().direct_space_state
	var best: Player = null
	var best_d := INF
	var best_pt := Vector3.ZERO
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
		var cone := CLOSE_CONE_DEG if to.length() < CLOSE else CONE_DEG
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
	Game.begin_melee_ctx(attacker, origin) # SURF / DROP KILL work with the bash too
	var r := best.apply_hit(best_pt, -dir, DAMAGE, false, killer_id, WEAPON_ID, 1.0, attacker.global_position)
	Game.end_melee_ctx()
	out.hit = int(r.get("damage", 0)) > 0
	out.killed = bool(r.get("killed", false))
	return out


func forget(peer_id: int) -> void:
	_last.erase(peer_id)


func reset() -> void:
	_last.clear()
