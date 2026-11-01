class_name MatchFlow
extends RefCounted
## Round and match flow (#106): round start/freeze/end, intermission, late-join state, leaving to menu,
## leaders and sorted scores, LINE speed strips and move tricks, pings and the live roster. Static helpers on
## the Game autoload `game`; Game keeps the state, signals and every @rpc.


## FFA round end: `winner_name` is the player. round_ended carries the peer id (TDM: the team id).
static func end_round_player(game: GameState, peer_id: int) -> void:
	game._round_active = false
	game.clear_radar()
	var winner_name := game._display_name_for(peer_id)
	if game.scores.has(peer_id):
		winner_name = str(game.scores[peer_id].name)
	if peer_id == 0:
		winner_name = "Nobody"
	game.round_ended.emit(peer_id, winner_name, game.scores.duplicate())
	if game.is_networked():
		game.sync_round_end.rpc(peer_id, winner_name, game.scores.duplicate())


## TDM round end: winner is a team; notifies every machine.
static func end_round_team(game: GameState, team_id: int) -> void:
	game._round_active = false
	game.clear_radar()
	var winner_name: String = game.TEAM_NAMES[clampi(team_id, 0, game.TEAM_NAMES.size() - 1)]
	game.round_ended.emit(team_id, winner_name, game.scores.duplicate())
	if game.is_networked():
		game.sync_round_end.rpc(team_id, winner_name, game.scores.duplicate())


## Starts the intermission here and, on the server, everywhere.
static func notify_intermission(game: GameState) -> void:
	game.intermission_started.emit()
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_intermission.rpc()


## Resets scores, trick/combo state and streaks for a new round.
static func start_round(game: GameState) -> void:
	game._round_timer = 0.0
	game._round_active = false # timer starts after freeze
	MatchRules.clear_round_state(game)
	game.team_kills = [0, 0]
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_team_kills.rpc(0, 0)
	for id in game.scores:
		game.scores[id].style = 0
		game.scores[id].deaths = 0
		game._apply_score(id, 0, str(game.scores[id].name), int(game.scores[id].get("team", 0)))
		if game.is_networked() and game.multiplayer.is_server():
			game.sync_score.rpc(id, 0, str(game.scores[id].name), int(game.scores[id].team), 0)
			game.sync_deaths.rpc(id, 0)
	game._clear_round_streaks()


## Freeze is over: the round clock starts.
static func end_freeze(game: GameState) -> void:
	game._round_active = true
	game._round_timer = 0.0
	game.set_round_frozen(false)
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_round_time.rpc(game.round_time)


## Late joiner: scores, team totals, freeze, and clock, so the HUD is right from the first frame.
static func send_match_state(game: GameState, peer_id: int) -> void:
	if not game.is_networked() or not game.multiplayer.is_server():
		return
	game.sync_match_config.rpc_id(peer_id, String(game.map_id), game.mode, game.kill_limit, game.round_time)
	var scores_arr := get_scores(game)
	if scores_arr.size() > 0:
		game.sync_all_scores.rpc_id(peer_id, scores_arr)
	game.sync_team_kills.rpc_id(peer_id, int(game.team_kills[0]), int(game.team_kills[1]))
	if game.round_frozen:
		game.sync_round_frozen.rpc_id(peer_id, true)
	if game.killcam_active:
		game.killcam.send_lock_to(peer_id)
	if game._round_active:
		game.sync_round_time.rpc_id(peer_id, game.get_round_time_left())


## Leave to menu: nothing from the old session may leak into the next one.
static func reset_session(game: GameState) -> void:
	game._combos.clear()
	if game.freeze_grade:
		game.freeze_grade.clear()
	game._tension_final = false
	if game._tension:
		game._tension.stop()
	PhysFx.clear()
	game.scores.clear()
	game.pings.clear()
	game.net_hp.clear()
	game._regen_dirty.clear()
	game.lobby.clear()
	game.streak_progress.clear()
	game.streak_charges.clear()
	game.streak_earned.clear()
	game.rc_view = false
	game._rc_done.clear()
	game.pending_names.clear()
	game.pending_teams.clear()
	game._fire_credit.clear()
	game.team_kills = [0, 0]
	game.in_lobby = false
	game.round_frozen = false
	game.killcam_active = false
	MatchRules.clear_round_state(game)
	game._shot_ctx = {}
	if game.killcam:
		game.killcam.reset()
	if game.melee:
		game.melee.reset()
	if game.impacts:
		game.impacts.clear()
	if game.loadouts:
		game.loadouts.reset()
	game.clear_radar()
	game._round_active = false
	game._round_timer = 0.0
	game.stop_round_sting()
	Engine.time_scale = 1.0
	for id in game._grenade_visuals:
		var vis: Node = game._grenade_visuals[id]
		if is_instance_valid(vis):
			vis.queue_free()
	game._grenade_visuals.clear()
	game._grenade_predicted.clear()
	game._grenade_done.clear()
	for g in game.get_tree().get_nodes_in_group("grenade"):
		g.queue_free()
	game._knife_visuals.clear()
	for k in game.get_tree().get_nodes_in_group("knife"):
		k.queue_free()


## TDM: the leading team (ties: team A).
static func get_leader(game: GameState) -> int:
	if game.team_score(game.TEAM_A) >= game.team_score(game.TEAM_B):
		return game.TEAM_A
	return game.TEAM_B


## FFA leader: most kills; a tie goes to the name that sorts first (same order as the board).
static func top_player(game: GameState) -> int:
	var board := get_scores(game)
	if board.is_empty() or int(board[0].get(game.score_word(), 0)) <= 0:
		return 0
	return int(board[0].peer_id)


## Score rows (peer, name, kills, team, style, deaths, ...) for the HUD and scoreboard.
static func get_scores(game: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in game.scores:
		out.append({
			"peer_id": id,
			"name": game.scores[id].name,
			"kills": game.scores[id].kills,
			"team": int(game.scores[id].get("team", 0)),
			"style": int(game.scores[id].get("style", 0)),
			"deaths": int(game.scores[id].get("deaths", 0)),
			"ping": int(game.pings.get(id, -1)),
		})
	out.sort_custom(game._sort_scores)
	return out


## Host is 0 ms. Bots are -1 (shown as —). Clients get ENet RTT from the server.
static func sample_pings(game: GameState) -> void:
	if not game.is_networked() or not game.multiplayer.is_server():
		return
	game.pings[game.multiplayer.get_unique_id()] = 0
	var enet := game.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		for id in game.multiplayer.get_peers():
			var ep := enet.get_peer(int(id))
			if ep == null or not ep.is_active():
				continue
			game.pings[int(id)] = int(ep.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	for id in game.scores:
		if int(id) < 0:
			game.pings[id] = -1
	if not game.multiplayer.get_peers().is_empty():
		game.sync_pings.rpc(game.pings)


## Match authority. A human pawn crossing a speed strip fast enough banks LINE (or LINE ×2).
## The segment test catches a snapshot that steps through the box. Bots never surf, so they skip it.
## is_best stays false: a strip is not a kill, and it must not replace the round's killcam.
static func tick_lines(game: GameState, delta: float) -> void:
	if not game._is_match_authority():
		return
	decay_line_clocks(game, delta)
	var strips := game.get_tree().get_nodes_in_group("speed_strip")
	if strips.is_empty():
		return
	for n in game.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_bot or p.is_dead:
			continue
		var prev: Vector3 = game._line_pos.get(p.peer_id, p.global_position)
		var step := p.global_position - prev
		game._line_pos[p.peer_id] = p.global_position
		if step.length() > Player.STRIP_TELEPORT_M:
			continue
		var spd := Vector2(step.x, step.z).length() / maxf(delta, 0.0001)
		if spd < Player.STRIP_SPEED:
			continue
		for s in strips:
			var strip := s as Node3D
			if strip == null or not Player.segment_hits_strip(strip, prev, p.global_position):
				continue
			award_line(game, p.peer_id, str(strip.name))
			break


## Counts down LINE strip cooldowns and chains.
static func decay_line_clocks(game: GameState, delta: float) -> void:
	var gone: Array[int] = []
	for id in game._line_cd:
		var left: Dictionary = game._line_cd[id]
		var names: Array = left.keys()
		for sname in names:
			left[sname] = float(left[sname]) - delta
			if float(left[sname]) <= 0.0:
				left.erase(sname)
		if left.is_empty():
			gone.append(int(id))
	for id in gone:
		game._line_cd.erase(id)
	gone.clear()
	for id in game._line_chain:
		var row: Array = game._line_chain[id]
		row[1] = float(row[1]) - delta
		if float(row[1]) <= 0.0:
			gone.append(int(id))
	for id in gone:
		game._line_chain.erase(id)


## #80: a movement trick that is not a kill (WALL TO WALL). Same wire as LINE.
static func award_move_trick(game: GameState, peer_id: int, trick: StringName) -> void:
	if not game._is_match_authority() or not game._round_active or not game.scores.has(peer_id):
		return
	var pts := int(Style.POINTS.get(trick, 0))
	if pts <= 0:
		return
	var total := pts + int(game.scores[peer_id].get("style", 0))
	game._trick_seq += 1
	var packed := Style.pack([trick])
	game._apply_trick(peer_id, 0, packed, pts, 1.0, total, game._trick_seq, false)
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_trick.rpc(peer_id, 0, packed, pts, 1.0, total, game._trick_seq, false)


## Same wire as a trickshot, without the kill chain and without touching best_trick.
static func award_line(game: GameState, peer_id: int, strip_name: String) -> void:
	if not game.scores.has(peer_id):
		return
	var cd: Dictionary = game._line_cd.get(peer_id, {})
	if float(cd.get(strip_name, 0.0)) > 0.0:
		return
	cd[strip_name] = Player.STRIP_COOLDOWN
	game._line_cd[peer_id] = cd
	var trick := Style.LINE
	var prev: Array = game._line_chain.get(peer_id, ["", 0.0])
	if str(prev[0]) != "" and str(prev[0]) != strip_name and float(prev[1]) > 0.0:
		trick = Style.LINE_X2
	game._line_chain[peer_id] = [strip_name, Player.CARRY_TIME]
	var pts := int(Style.POINTS[trick])
	var total := pts + int(game.scores[peer_id].get("style", 0))
	game._trick_seq += 1
	var packed := Style.pack([trick])
	game._apply_trick(peer_id, 0, packed, pts, 1.0, total, game._trick_seq, false)
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_trick.rpc(peer_id, 0, packed, pts, 1.0, total, game._trick_seq, false)


## Peers that are connected right now (server included).
static func live_peer_ids(game: GameState) -> Array:
	var ids: Array = []
	for n in game.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and not p.is_queued_for_deletion():
			ids.append(p.peer_id)
	return ids


## Server: sends the live peer list to everyone.
static func broadcast_roster(game: GameState) -> void:
	if not game.is_networked() or not game.multiplayer.is_server():
		return
	game.sync_roster.rpc(live_peer_ids(game))
