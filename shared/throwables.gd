class_name Throwables
extends RefCounted
## Frag grenades and throwing knives (#106): authority throw, client prediction, visuals, knife hits.
## Static helpers on the Game autoload `game`; Game keeps the state and every @rpc (request_*, sync_*).


## Next network id for a grenade (authority).
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


## The client copy of grenade `net_id`, spawned on first sight.
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


## Server (request_grenade): re-checks the throw origin; ammo, death and freeze are throw_grenade's.
static func request_grenade(game: GameState, origin: Vector3, dir: Vector3, client_seq: int) -> void:
	if not game.multiplayer.is_server():
		return
	var thrower := game.player_for_peer(Lobby.sender(game))
	if thrower == null or dir.length_squared() < 0.0001 or not game.origin_plausible(thrower, origin):
		return
	throw_grenade(game, thrower, origin, dir, client_seq)


static func set_grenade_count(game: GameState, peer_id: int, n: int) -> void:
	var p := game.player_for_peer(peer_id)
	if p == null:
		return
	p.grenades = n
	p._notify_grenades()


## Client (sync_grenade_spawn): a visual copy flying on its own from the spawn velocity; damage stays on
## the server grenade. The thrower's own predicted copy is adopted instead of spawning a second one.
static func on_grenade_spawn(game: GameState, net_id: int, pos: Vector3, vel: Vector3, thrower_peer: int, client_seq: int) -> void:
	if game.multiplayer.is_server() or game._grenade_done.has(net_id):
		return
	if thrower_peer == game.multiplayer.get_unique_id() and game._grenade_predicted.has(client_seq):
		var pred = game._grenade_predicted[client_seq]
		game._grenade_predicted.erase(client_seq)
		if is_instance_valid(pred):
			game._grenade_visuals[net_id] = pred
			return
	var existing = game._grenade_visuals.get(net_id)
	if is_instance_valid(existing):
		(existing as Grenade).velocity = vel # a pose beat the spawn here; give it the real arc
		return
	grenade_visual(game, net_id, pos, vel)


## Client (sync_grenade_pose). Unreliable can arrive after the reliable boom; that would leave a ghost.
static func on_grenade_pose(game: GameState, net_id: int, pos: Vector3) -> void:
	if game.multiplayer.is_server() or game._grenade_done.has(net_id):
		return
	var g := grenade_visual(game, net_id, pos, Vector3.ZERO) as Grenade
	if g:
		g.apply_net_pose(pos)


## Client (sync_grenade_boom): drop the flying mesh, then play the same boom the server already showed.
static func on_grenade_boom(game: GameState, pos: Vector3, net_id: int) -> void:
	if game.multiplayer.is_server():
		return
	game._grenade_done[net_id] = true
	if game._grenade_visuals.has(net_id):
		var vis: Node = game._grenade_visuals[net_id]
		game._grenade_visuals.erase(net_id)
		if is_instance_valid(vis):
			vis.queue_free()
	Grenade.play_boom(pos)


## Server (request_knife): humans only, with a plausible origin.
static func request_knife(game: GameState, origin: Vector3, dir: Vector3) -> void:
	if not game.multiplayer.is_server():
		return
	var thrower := game.player_for_peer(Lobby.sender(game))
	if thrower == null or thrower.is_bot or dir.length_squared() < 0.0001 or not game.origin_plausible(thrower, origin):
		return
	throw_knife(game, thrower, origin, dir)


## Every machine (sync_knife_count). A count that drops is a throw, and this RPC already reaches every
## client: that is how the body animation gets the right thrower without a new field in sync_knife_spawn
## (#25). A refill (respawn, Game reset) goes up and stays silent.
static func set_knife_count(game: GameState, peer_id: int, n: int) -> void:
	var p := game.player_for_peer(peer_id)
	if p == null:
		return
	if n < p.knives:
		p.play_throw_anim()
	p.knives = n
	p._notify_grenades()


## Client (sync_knife_spawn): a visual copy flies from the release; on_knife_done ends it.
static func on_knife_spawn(game: GameState, net_id: int, pos: Vector3, vel: Vector3) -> void:
	if game.multiplayer.is_server():
		return
	var scene := game.get_tree().current_scene
	if scene == null:
		return
	var k := ThrowingKnife.new()
	k.is_visual = true
	k.velocity = vel
	k.origin = pos
	scene.add_child(k)
	k.global_position = pos
	game._knife_visuals[net_id] = k


## Client (sync_knife_done). `end`: ThrowingKnife.END_* (stuck in the world at `pos` for a moment, hit a
## body, or flew off).
static func on_knife_done(game: GameState, net_id: int, pos: Vector3, normal: Vector3, end: int) -> void:
	if game.multiplayer.is_server():
		return
	var k := game._knife_visuals.get(net_id) as ThrowingKnife
	game._knife_visuals.erase(net_id)
	if k == null or not is_instance_valid(k):
		return
	if end == ThrowingKnife.END_STUCK:
		k.stick(pos, normal)
		return
	k.global_position = pos
	if end == ThrowingKnife.END_BODY:
		k.play_flesh()
	k.queue_free()
