class_name StreakSelect
extends RefCounted
## A player's killstreak pick (#387): the local choice in settings, the server's accepted copy per
## peer, and the RPC round trip. The server decides which streaks a player earns, so a client sends
## its pick, the server validates it and echoes the accepted list back; the HUD then shows what the
## server will actually award. Static helpers on the Game autoload `g`; Game keeps the state and the
## @rpc (request_streak_choice, sync_streak_choice), like every other RPC in the game.


## The server's accepted pick for a peer. Bots get the default without the streaks they may not use.
static func choice_for(g: GameState, peer_id: int) -> Array:
	if peer_id < 0:
		return StreakDefs.bot_ids()
	if g.streak_choices.has(peer_id):
		return g.streak_choices[peer_id]
	return StreakDefs.default_ids()


## The streak id in a slot, or &"" for an empty slot.
static func id_at(g: GameState, peer_id: int, slot: int) -> StringName:
	var c := choice_for(g, peer_id)
	if slot < 0 or slot >= c.size():
		return &""
	return StringName(c[slot])


## The slot a streak sits in for a peer, or -1 when it is not picked.
static func slot_for(g: GameState, peer_id: int, id: StringName) -> int:
	return choice_for(g, peer_id).find(id)


## Local pick from the menu: validate, keep it, save it, and tell the server when this is a client.
static func set_local(g: GameState, raw: Variant) -> Array:
	var ids := StreakDefs.sanitize(raw)
	g.streak_choice = ids
	GameSettings.save_settings(g)
	if g.is_networked() and not g.multiplayer.is_server():
		g.request_streak_choice.rpc_id(1, ids)
	else:
		server_submit(g, g.multiplayer.get_unique_id() if g.is_networked() else 1, ids)
	return ids


## Server (request_streak_choice): validate and store the sender's pick, then echo what was accepted.
## An invalid pick is replaced by the default, so a forged RPC cannot grant a streak the game lacks.
static func server_submit(g: GameState, peer_id: int, raw: Variant) -> Array:
	if not g._is_match_authority() or peer_id <= 0:
		return []
	var ids := StreakDefs.sanitize(raw)
	g.streak_choices[peer_id] = ids
	if g.is_networked():
		g.sync_streak_choice.rpc_id(peer_id, ids)
	return ids


## Client (sync_streak_choice): the server's accepted pick is what the HUD shows.
static func on_sync(g: GameState, ids: Array) -> void:
	g.streak_choice = StreakDefs.sanitize(ids)
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_streak_choice(g.streak_choice)


## New round: keep the pick (it is the player's, not the round's), only the charges go.
static func forget(g: GameState, peer_id: int) -> void:
	g.streak_choices.erase(peer_id)
