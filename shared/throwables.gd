class_name Throwables
extends RefCounted
## Frag grenades and throwing knives (#106): authority throw, client prediction, visuals, knife hits.
## Static helpers on the Game autoload `game`; Game keeps the state and every @rpc (request_*, sync_*).


static func next_grenade_id(game: GameState) -> int:
	game._grenade_seq += 1
	return game._grenade_seq


## Authority only. Clients ask via request_grenade; the count RPC updates their HUD.
static func throw_grenade(game: GameState, thrower: Player, origin: Vector3, dir: Vector3, client_seq := 0) -> void:
	if thrower == null or thrower.is_dead or thrower.grenades <= 0 or game.play_locked():
		return
	if game.is_networked() and not game.multiplayer.is_server():
		return
	thrower.grenades -= 1
	thrower._notify_grenades()
	if game.is_networked():
		game.sync_grenade_count.rpc(thrower.peer_id, thrower.grenades)
	Grenade.launch(thrower, origin, dir, client_seq)


## Client prediction: the thrower sees their grenade leave the hand at once instead of a ping later.
## `seq` ties it to the server's spawn RPC, which then adopts this copy.
static func predict_grenade(game: GameState, thrower: Player, origin: Vector3, dir: Vector3) -> int:
	var scene := game.get_tree().current_scene
	if scene == null or thrower == null:
		return 0
	game._grenade_pred_seq += 1
	game._grenade_predicted[game._grenade_pred_seq] = Grenade.spawn_visual(scene, origin, Grenade.initial_velocity(dir))
	return game._grenade_pred_seq


static func grenade_visual(game: GameState, net_id: int, pos: Vector3, vel: Vector3) -> Node3D:
	if game._grenade_visuals.has(net_id) and is_instance_valid(game._grenade_visuals[net_id]):
		return game._grenade_visuals[net_id]
	var scene := game.get_tree().current_scene
	if scene == null:
		return null
	var g := Grenade.spawn_visual(scene, pos, vel)
	game._grenade_visuals[net_id] = g
	return g


## Authority only. Clients ask via request_knife.
static func throw_knife(game: GameState, thrower: Player, origin: Vector3, dir: Vector3) -> void:
	if thrower == null or thrower.is_dead or thrower.knives <= 0 or game.play_locked():
		return
	if game.is_networked() and not game.multiplayer.is_server():
		return
	thrower.knives -= 1
	thrower._notify_grenades()
	if game.is_networked():
		game.sync_knife_count.rpc(thrower.peer_id, thrower.knives)
	ThrowingKnife.launch(thrower, origin, dir)


## Server knife hit a body: one-hit kill, the throw is the "shot" for tricks (YEET).
static func knife_hit(game: GameState, knife: ThrowingKnife, victim: Player, point: Vector3, normal: Vector3) -> void:
	var thrower := game.player_for_peer(knife.thrower_id)
	if thrower:
		game._shot_ctx = {"shooter": thrower, "origin": knife.origin, "scoped": false, "burst": {}, "knife_air": knife.airborne}
	var killer_id := knife.thrower_id
	if killer_id <= 0 and thrower:
		killer_id = thrower._owner_peer()
	var res := victim.apply_hit(point, normal, ThrowingKnife.DAMAGE, false, killer_id, &"knife", 1.0, knife.origin)
	game._shot_ctx = {}
	if res.get("damage", 0) <= 0 or thrower == null:
		return
	if thrower.is_local():
		game.hit_confirmed.emit(bool(res.killed), false)
		if thrower.weapon:
			thrower.weapon.play_hit_feedback(bool(res.killed), false)
	elif game.is_networked() and not thrower.is_bot and thrower.peer_id > 0:
		game.notify_hit.rpc_id(thrower.peer_id, bool(res.killed), false)
