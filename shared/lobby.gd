class_name Lobby
extends RefCounted
## Lobby, joining and chat (#106): participants and names (clean, unique, pending), lobby roster,
## join/leave notices, chat relay. Static helpers on the Game autoload `game`; Game keeps the state and every @rpc.


## Trimmed to NAME_MAX, one line. Used for every name that reaches the scoreboard.
static func clean_name(game: GameState, n: String, fallback: String = "Player") -> String:
	n = n.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if n.length() > game.NAME_MAX:
		n = n.substr(0, game.NAME_MAX).strip_edges()
	return n if n != "" else fallback


## Server: `n` cleaned and made unique among connected players, bots and lobby rows,
## case-insensitive. A taken name gets " (2)", " (3)", ... `peer_id`'s own current name never counts.
static func unique_name(game: GameState, peer_id: int, n: String) -> String:
	n = clean_name(game, n)
	var taken := {}
	for other in game.scores:
		if int(other) != peer_id:
			taken[str(game.scores[other].get("name", "")).to_lower()] = true
	for other in game.lobby:
		if int(other) != peer_id:
			taken[str(game.lobby[other].get("name", "")).to_lower()] = true
	for other in game.pending_names:
		if int(other) != peer_id:
			taken[str(game.pending_names[other]).to_lower()] = true
	for node in game.get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p != null and p.peer_id != peer_id:
			taken[p.display_name.to_lower()] = true
	if not taken.has(n.to_lower()):
		return n
	var i := 2
	while true:
		var suffix := " (%d)" % i
		var cand := n.substr(0, game.NAME_MAX - suffix.length()).strip_edges() + suffix
		if not taken.has(cand.to_lower()):
			return cand
		i += 1
	return n


## Our name as the server resolved it (e.g. "Gianni (2)"), else the typed one.
static func local_resolved_name(game: GameState) -> String:
	var me := game.multiplayer.get_unique_id() if game.is_networked() else 1
	if game.scores.has(me):
		return str(game.scores[me].get("name", game.player_name))
	if game.lobby.has(me):
		return str(game.lobby[me].get("name", game.player_name))
	return game.player_name


static func take_pending_name(game: GameState, peer_id: int, fallback: String) -> String:
	if game.pending_names.has(peer_id):
		var n: String = game.pending_names[peer_id]
		game.pending_names.erase(peer_id)
		return n
	return fallback


static func display_name_for(game: GameState, peer_id: int) -> String:
	var killer := game.player_for_peer(peer_id)
	if killer:
		return killer.display_name
	if peer_id < 0:
		return "Bot %d" % abs(peer_id)
	return "Player"


## Called when a pawn spawns (and for a killer without a row). `team` is the pawn's, so it always
## wins over a row made earlier by apply_display_name, and the fix is synced to everyone.
static func register_participant(game: GameState, peer_id: int, n: String, team: int = 0) -> void:
	if game.scores.has(peer_id):
		var existing: String = str(game.scores[peer_id].name)
		var incoming_placeholder := n == "" or n == "Player"
		var keep_existing := existing != "" and existing != "Player"
		var new_name := existing if n == "" or (incoming_placeholder and keep_existing) else n
		if new_name == existing and int(game.scores[peer_id].get("team", -1)) == team:
			return
		game._apply_score(peer_id, int(game.scores[peer_id].kills), new_name, team)
		if game.is_networked() and game.multiplayer.is_server():
			game.sync_score.rpc(peer_id, int(game.scores[peer_id].kills), new_name, team)
		return
	game._apply_score(peer_id, 0, n, team)
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_score.rpc(peer_id, 0, n, team)


static func set_lobby_member(game: GameState, peer_id: int, n: String, team: int) -> void:
	if not game._is_match_authority():
		return
	game.lobby[peer_id] = {"name": n, "team": clampi(team, game.TEAM_A, game.TEAM_B)}
	push_lobby(game)


static func remove_lobby_member(game: GameState, peer_id: int) -> void:
	if not game.lobby.has(peer_id):
		return
	game.lobby.erase(peer_id)
	if game._is_match_authority():
		push_lobby(game)


static func push_lobby(game: GameState) -> void:
	game.lobby_changed.emit()
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_lobby.rpc(game.lobby)


static func announce_presence(game: GameState, player_name: String, joined: bool, team: int) -> void:
	if not game._is_match_authority():
		return
	game.presence.emit(player_name, joined, team)
	if game.is_networked():
		game.sync_presence.rpc(player_name, joined, team)


## All-chat. Clients send to the server; host stamps name/team and broadcasts.
static func send_chat(game: GameState, text: String) -> void:
	text = text.strip_edges()
	if text.length() > game.CHAT_MAX:
		text = text.substr(0, game.CHAT_MAX)
	if text == "":
		return
	if not game.is_networked():
		deliver_chat(game, game.player_name, game._local_team(), text)
		return
	if game.multiplayer.is_server():
		relay_chat(game, game.multiplayer.get_unique_id(), text)
	else:
		game.submit_chat.rpc_id(1, text)


## Never trust the client for the display name — look up the pawn / scoreboard.
static func relay_chat(game: GameState, peer_id: int, text: String) -> void:
	var p := game.player_for_peer(peer_id)
	var n := display_name_for(game, peer_id)
	var team := 0
	if p:
		n = p.display_name
		team = p.team_id
	elif game.scores.has(peer_id):
		n = str(game.scores[peer_id].name)
		team = int(game.scores[peer_id].get("team", 0))
	game.broadcast_chat.rpc(n, team, text)


static func deliver_chat(game: GameState, n: String, team: int, text: String) -> void:
	game.chat_message.emit(n, team, text)
