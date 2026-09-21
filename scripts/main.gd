extends Node3D
## Arena root: menu, match flow (warmup → play → end → intermission), and pawn spawn.
## Server (or offline host) is the only one that creates players/bots.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
# Inside the L-cover pockets, not in the walls. Blue = +Z, Orange = -Z.
const TEAM_A_SPAWNS := [
	Vector3(0.0, 0.0, 26.5),
	Vector3(3.0, 0.0, 26.5),
	Vector3(-3.0, 0.0, 26.5),
	Vector3(10.0, 0.0, 24.5),
	Vector3(-10.0, 0.0, 24.5),
]
const TEAM_B_SPAWNS := [
	Vector3(0.0, 0.0, -26.5),
	Vector3(3.0, 0.0, -26.5),
	Vector3(-3.0, 0.0, -26.5),
	Vector3(10.0, 0.0, -24.5),
	Vector3(-10.0, 0.0, -24.5),
]

enum MatchState { WARMUP, FREEZE, PLAYING, ROUND_END, INTERMISSION }

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: Hud = $CanvasLayer/Hud
@onready var menu = $CanvasLayer/Menu
@onready var pause_ui = $CanvasLayer/Pause

var _leaving := false

var _spawn_i := [0, 0] # next spawn index per team
var _match_state := MatchState.WARMUP
var _state_timer := 0.0
var _bot_id_counter := -1 # bots use negative peer_ids: -1, -2, …


func _ready() -> void:
	DisplayServer.window_set_title("Gevechtspel")
	if has_node("MenuCamera"):
		$MenuCamera.global_position = Vector3(24, 14, 40)
		$MenuCamera.look_at(Vector3(0, 1.2, 0))
		$MenuCamera.current = true
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player_node
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Game.local_player_ready.connect(_on_local_player_ready)
	Game.round_ended.connect(_on_round_ended)
	Game.match_starting.connect(_on_match_starting)
	Game.lobby_changed.connect(_on_lobby_changed)
	menu.play_local_pressed.connect(_play_locally)
	menu.host_pressed.connect(_host_game)
	menu.connect_pressed.connect(_connect_to_server)
	if menu.has_signal("start_match_pressed"):
		menu.start_match_pressed.connect(_start_match_from_lobby)
	if menu.has_signal("lobby_team_picked"):
		menu.lobby_team_picked.connect(_lobby_pick_team)
	if menu.has_signal("lobby_leave_pressed"):
		menu.lobby_leave_pressed.connect(_leave_to_menu)
	if pause_ui:
		pause_ui.resume_pressed.connect(_resume_game)
		pause_ui.leave_pressed.connect(_leave_to_menu)
	call_deferred("_bake_nav")
	var args := _parse_args()
	if args.get("name", "") != "":
		Game.player_name = args["name"]
		menu.set_player_name(Game.player_name)
	if args.get("server", false):
		_start_server(int(args.get("port", Game.DEFAULT_PORT)), true)
		return
	if str(args.get("connect", "")) != "":
		menu.set_host_ip(str(args["connect"]))
		menu.set_host_port(int(args.get("port", Game.DEFAULT_PORT)))
		_connect_to_server()
		return
	menu.visible = true


## Runtime navmesh from arena collision (not GPU meshes).
func _bake_nav() -> void:
	var region := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var arena := get_node_or_null("Arena") as Node3D
	if region == null or arena == null:
		return
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.75
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 46.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, arena)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	region.navigation_mesh = nav_mesh


func _parse_args() -> Dictionary:
	var out := {"server": false, "port": Game.DEFAULT_PORT, "connect": "", "name": ""}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--server":
				out.server = true
			"--port":
				i += 1
				if i < args.size():
					out.port = int(args[i])
			"--connect":
				i += 1
				if i < args.size():
					var raw := args[i]
					if raw.contains(":"):
						var parts := raw.split(":")
						out.connect = parts[0]
						out.port = int(parts[1])
					else:
						out.connect = raw
			"--name":
				i += 1
				if i < args.size():
					out.name = args[i]
		i += 1
	return out


## Match clock. Clients do not tick this; they get time/scores over RPC.
func _process(delta: float) -> void:
	if Game.in_lobby:
		return
	if not multiplayer.is_server() and not Game.is_offline:
		return
	if _match_state == MatchState.WARMUP:
		_tick_warmup(delta)
	elif _match_state == MatchState.FREEZE:
		_tick_freeze(delta)
	elif _match_state == MatchState.PLAYING:
		_tick_playing(delta)
	elif _match_state == MatchState.ROUND_END:
		_tick_round_end(delta)
	elif _match_state == MatchState.INTERMISSION:
		_tick_intermission(delta)


func _tick_warmup(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= Game.WARMUP_TIME:
		_start_round()


func _tick_playing(delta: float) -> void:
	if Game.update_round_timer(delta):
		return
	if Game.is_networked() and multiplayer.is_server():
		_state_timer += delta
		if _state_timer >= 1.0:
			_state_timer = 0.0
			Game.sync_round_time.rpc(Game.get_round_time_left())


func _tick_round_end(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= Game.ROUND_END_TIME:
		_start_intermission()


func _tick_intermission(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= Game.INTERMISSION_TIME:
		_reset_round()


func _tick_freeze(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= Game.FREEZE_TIME:
		Game.end_freeze()
		_match_state = MatchState.PLAYING
		_state_timer = 0.0
		_set_status("Round started!")


func _start_round() -> void:
	_match_state = MatchState.FREEZE
	_state_timer = 0.0
	Game.start_round()
	_spawn_all_players()
	_fill_bots()
	Game.set_round_frozen(true)
	_set_status("Get ready")


func _spawn_all_players() -> void:
	_respawn_all_pawns()


## Clients own their pawn transforms — must RPC respawn, not only move the server copy.
func _respawn_all_pawns() -> void:
	for n in players_root.get_children():
		var p := n as Player
		if p == null:
			continue
		if Game.is_networked():
			Game.broadcast_respawn.rpc(p.peer_id)
		else:
			p.apply_respawn_state()


func _enter_play() -> void:
	menu.visible = false
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()
	hud.visible = true
	Game.chat_open = false
	Game.pause_open = false
	_disable_menu_camera()


func _open_lobby(status: String) -> void:
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if has_node("MenuCamera"):
		$MenuCamera.current = true
	_set_status(status)
	if menu.has_method("show_screen"):
		menu.show_screen("lobby")
	_on_lobby_changed()


func _on_lobby_changed() -> void:
	if menu.has_method("refresh_lobby"):
		menu.refresh_lobby(Game.lobby, multiplayer.is_server())


func _on_match_starting() -> void:
	Game.in_lobby = false
	_enter_play()
	if not multiplayer.is_server():
		return
	for id in Game.lobby:
		var e: Dictionary = Game.lobby[id]
		_spawn_player(int(id), int(e.get("team", 0)))
	_fill_bots()
	broadcast_pawns()
	_start_round()


func _start_match_from_lobby() -> void:
	if not multiplayer.is_server() or not Game.in_lobby:
		return
	Game.begin_match.rpc()


func _lobby_pick_team(team: int) -> void:
	if menu.has_method("set_team"):
		menu.set_team(team)
	if Game.in_lobby and Game.is_networked():
		if multiplayer.is_server():
			Game.set_lobby_member(1, Game.player_name, team)
		else:
			Game.request_lobby_team.rpc_id(1, team)
	elif Game.in_lobby:
		Game.set_lobby_member(1, Game.player_name, team)


func _disable_menu_camera() -> void:
	if has_node("MenuCamera"):
		$MenuCamera.current = false


func _play_locally() -> void:
	Game.is_offline = true
	Game.is_dedicated = false
	Game.player_name = menu.player_name()
	if Game.player_name == "":
		Game.player_name = "Player"
	Game.preferred_team = menu.selected_team()
	_enter_play()
	_match_state = MatchState.WARMUP
	_state_timer = 0.0
	_spawn_player(multiplayer.get_unique_id(), Game.preferred_team)
	_fill_bots()


func _host_game() -> void:
	Game.player_name = menu.player_name()
	if Game.player_name == "":
		Game.player_name = "Host"
	Game.preferred_team = menu.selected_team()
	_start_server(menu.host_port(), false)


func _start_server(port: int, dedicated: bool) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 10)
	if err != OK:
		_set_status("Could not host on port %d (err %d)" % [port, err])
		print("SERVER: create_server failed with err %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	Game.is_offline = false
	Game.is_dedicated = dedicated
	print("SERVER: Server started on port %d, dedicated=%s" % [port, dedicated])
	if dedicated:
		_enter_play()
		hud.visible = false
		DisplayServer.window_set_title("Gevechtspel server :%d" % port)
		print("Dedicated server on port ", port)
		_match_state = MatchState.WARMUP
		_state_timer = 0.0
		_fill_bots()
		return
	_open_lobby("Hosting on port %d — waiting in lobby." % port)
	Game.in_lobby = true
	Game.set_lobby_member(1, Game.player_name, Game.preferred_team)


func _connect_to_server() -> void:
	Game.player_name = menu.player_name()
	if Game.player_name == "":
		Game.player_name = "Player"
	Game.preferred_team = menu.selected_team()
	var ip: String = menu.host_ip()
	var port: int = menu.host_port()
	print("CLIENT: Creating client peer for %s:%d" % [ip, port])
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_set_status("Connect failed to start (err %d)" % err)
		print("CLIENT: create_client failed with err %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	Game.is_offline = false
	Game.is_dedicated = false
	_set_status("Connecting to %s:%d …" % [ip, port])
	print("CLIENT: multiplayer_peer set, waiting for connection...")


func _on_connected_to_server() -> void:
	print("CLIENT: Connected to server!")
	DisplayServer.window_set_title("Gevechtspel — %s" % Game.player_name)
	Game.in_lobby = true
	_open_lobby("Connected — waiting for host to start.")
	Game.submit_display_name.rpc_id(1, Game.player_name, Game.preferred_team)


func _on_connection_failed() -> void:
	print("CLIENT: Connection failed!")
	_set_status("Connection failed. Is the host running, and is the port free?")
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.visible = false
	Game.is_offline = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if has_node("MenuCamera"):
		$MenuCamera.current = true


func _on_server_disconnected() -> void:
	print("CLIENT: Server disconnected!")
	_leave_to_menu()
	_set_status("Server left.")


## Late join: defer so MultiplayerSpawner can replicate existing pawns first.
func _on_peer_connected(id: int) -> void:
	print("SERVER: Peer connected: %d" % id)
	if not multiplayer.is_server():
		return
	if id == 1:
		return
	if Game.in_lobby:
		return
	call_deferred("_finish_peer_join", id)


func _unhandled_input(event: InputEvent) -> void:
	if not hud.visible or Game.chat_open or Game.pause_open:
		return
	if event.is_action_pressed("toggle_mouse"):
		_open_pause()
		get_viewport().set_input_as_handled()


func _open_pause() -> void:
	if pause_ui:
		pause_ui.open()


func _resume_game() -> void:
	if pause_ui:
		pause_ui.close()


func _leave_to_menu() -> void:
	_leaving = true
	if pause_ui:
		pause_ui.close(false)
	get_tree().paused = false
	Game.pause_open = false
	Game.chat_open = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	for c in players_root.get_children():
		c.queue_free()
	Game.scores.clear()
	Game.pings.clear()
	Game.net_hp.clear()
	Game.lobby.clear()
	Game.in_lobby = false
	Game.is_offline = true
	Game.is_dedicated = false
	_bot_id_counter = -1
	_spawn_i = [0, 0]
	hud.visible = false
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	if menu.has_method("show_screen"):
		menu.show_screen("home")
	if has_node("MenuCamera"):
		$MenuCamera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_leaving = false


func _on_peer_disconnected(id: int) -> void:
	if _leaving:
		return
	if Game.in_lobby:
		Game.remove_lobby_member(id)
		return
	print("SERVER: Peer disconnected: %d" % id)
	var team := 0
	var leave_name := Game._display_name_for(id)
	var node := players_root.get_node_or_null(str(id))
	if node is Player:
		team = (node as Player).team_id
		leave_name = (node as Player).display_name
		node.queue_free()
	elif Game.scores.has(id):
		leave_name = str(Game.scores[id].name)
		team = int(Game.scores[id].get("team", 0))
	Game.announce_presence(leave_name, false, team)
	Game.clear_peer_hp(id)
	Game.scores.erase(id)
	_spawn_bot(team)


func _spawn_player(peer_id: int, team: int = -1) -> void:
	print("SERVER: _spawn_player called for peer %d" % peer_id)
	if players_root.get_node_or_null(str(peer_id)):
		print("SERVER: Player %d already exists" % peer_id)
		return
	if team < 0:
		if Game.pending_teams.has(peer_id):
			team = int(Game.pending_teams[peer_id])
		else:
			team = _team_for_human()
	team = clampi(team, Game.TEAM_A, Game.TEAM_B)
	var pos := _next_spawn(team)
	var fallback: String = Game.player_name if peer_id == multiplayer.get_unique_id() else "Player"
	var n: String = Game.take_pending_name(peer_id, fallback)
	print("SERVER: Spawning player %d team %d at %s with name %s" % [peer_id, team, pos, n])
	_add_pawn({"id": peer_id, "pos": pos, "n": n, "bot": false, "team": team})


## Spawn the human, then trim extra bots so each team stays at TEAM_SIZE.
func _finish_peer_join(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Wait a beat so submit_display_name (name + team) can land first.
	var join_id := id
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		_spawn_player(join_id)
		_trim_bots()
		_after_join_spawn(join_id)
	)


func _after_join_spawn(id: int) -> void:
	var join_id := id
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		var joiner := Game.player_for_peer(join_id)
		if joiner:
			Game.announce_presence(joiner.display_name, true, joiner.team_id)
	)
	var scores_arr := Game.get_scores()
	if scores_arr.size() > 0:
		Game.sync_all_scores.rpc_id(id, scores_arr)
	broadcast_pawns()
	get_tree().create_timer(0.3).timeout.connect(broadcast_pawns)
	get_tree().create_timer(1.0).timeout.connect(broadcast_pawns)


func _pawn_snapshot() -> Array:
	var out: Array = []
	for child in players_root.get_children():
		var p := child as Player
		if p == null or p.is_queued_for_deletion():
			continue
		out.append({
			"id": p.peer_id,
			"pos": p.global_position,
			"yaw": p.rotation.y,
			"pitch": p.head.rotation.x if p.head else 0.0,
			"n": p.display_name,
			"bot": p.is_bot,
			"team": p.team_id,
			"loadout": p.loadout_index,
		})
	return out


## Reliable snapshot so late joiners get bots even if the spawner missed them.
func broadcast_pawns() -> void:
	if not Game.is_networked() or not multiplayer.is_server():
		return
	sync_pawns.rpc(_pawn_snapshot())


@rpc("authority", "reliable")
func sync_pawns(list: Array) -> void:
	if multiplayer.is_server():
		return
	var wanted := {}
	for entry in list:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
			continue
		var id := int(entry["id"])
		wanted[id] = true
		var p := Game.player_for_peer(id)
		if p == null:
			var node_name := ("bot%d" % abs(id)) if bool(entry.get("bot", false)) else str(id)
			if players_root.get_node_or_null(node_name):
				p = players_root.get_node(node_name) as Player
			else:
				p = _spawn_player_node(entry) as Player
				if p and p.get_parent() == null:
					players_root.add_child(p, true)
		if p and p.is_bot:
			var pos: Vector3 = entry["pos"]
			p.apply_network_pose(pos, float(entry.get("yaw", 0.0)), float(entry.get("pitch", 0.0)))
			p.is_bot = true
			p.team_id = int(entry.get("team", p.team_id))
			p.loadout_index = int(entry.get("loadout", p.loadout_index))
			p._apply_bot_loadout()
			p._apply_team_visual()
	for child in players_root.get_children():
		var extra := child as Player
		if extra == null or extra.is_local() or extra.is_queued_for_deletion():
			continue
		if not wanted.has(extra.peer_id):
			extra.queue_free()


## Used by MultiplayerSpawner on every peer. `bot` pawns are always authority 1.
func _spawn_player_node(data: Variant) -> Node:
	var d: Dictionary = data
	if typeof(d) != TYPE_DICTIONARY or not d.has("id"):
		push_error("Bad player spawn payload: %s" % str(data))
		return Node.new()
	var p: Player = PLAYER_SCENE.instantiate()
	var id := int(d["id"])
	p.peer_id = id
	p.is_bot = bool(d.get("bot", false))
	p.team_id = int(d.get("team", 0))
	p.loadout_index = int(d.get("loadout", 0))
	p.name = ("bot%d" % abs(id)) if p.is_bot else str(id)
	p.display_name = str(d.get("n", "Player"))
	p.position = d["pos"]
	if p.is_bot:
		p.set_multiplayer_authority(1, true)
	else:
		p.set_multiplayer_authority(id, true)
	Game.set_hp(p, Player.MAX_HP)
	Game.register_participant(id, p.display_name, p.team_id)
	return p


func _add_pawn(data: Dictionary) -> void:
	if Game.is_offline:
		var p: Player = _spawn_player_node(data)
		players_root.add_child(p, true)
		return
	if not multiplayer.is_server():
		return
	spawner.spawn(data)


func _next_spawn(team: int) -> Vector3:
	var list: Array = TEAM_A_SPAWNS if team == Game.TEAM_A else TEAM_B_SPAWNS
	var i: int = int(_spawn_i[team]) % list.size()
	_spawn_i[team] = i + 1
	return list[i]


func _team_count(team: int) -> int:
	var n := 0
	for child in players_root.get_children():
		var p := child as Player
		if p and p.team_id == team and not p.is_queued_for_deletion():
			n += 1
	return n


func _human_count(team: int) -> int:
	var n := 0
	for child in players_root.get_children():
		var p := child as Player
		if p and not p.is_bot and p.team_id == team and not p.is_queued_for_deletion():
			n += 1
	return n


## First human → Blue, next → Orange (balance by human count, not bots).
func _team_for_human() -> int:
	if _human_count(Game.TEAM_A) <= _human_count(Game.TEAM_B):
		return Game.TEAM_A
	return Game.TEAM_B


func _smaller_team() -> int:
	if _team_count(Game.TEAM_A) <= _team_count(Game.TEAM_B):
		return Game.TEAM_A
	return Game.TEAM_B


## loadout = abs(id) % 4 → rifle / pistol / shotgun / sniper.
func _spawn_bot(team: int) -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	var id := _bot_id_counter
	_bot_id_counter -= 1
	var pos := _next_spawn(team)
	_add_pawn({
		"id": id,
		"pos": pos,
		"n": "Bot %d" % abs(id),
		"bot": true,
		"team": team,
		"loadout": abs(id) % 4,
	})


func _fill_bots() -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	for team in [Game.TEAM_A, Game.TEAM_B]:
		while _team_count(team) < Game.TEAM_SIZE:
			_spawn_bot(team)


func _first_bot_on(team: int) -> Player:
	for child in players_root.get_children():
		var p := child as Player
		if p and p.is_bot and p.team_id == team and not p.is_queued_for_deletion():
			return p
	return null


## Drop bots until each team is at most TEAM_SIZE (after a human joins).
func _trim_bots() -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	for team in [Game.TEAM_A, Game.TEAM_B]:
		while _team_count(team) > Game.TEAM_SIZE:
			var bot := _first_bot_on(team)
			if bot == null:
				break
			Game.scores.erase(bot.peer_id)
			bot.queue_free()


func _on_local_player_ready(player: Player) -> void:
	_disable_menu_camera()
	player.make_active_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.bind_player(player)
	DisplayServer.window_set_title("Gevechtspel — %s" % Game.player_name)


func _on_round_ended(_winner_peer_id: int, winner_name: String, _scores: Dictionary) -> void:
	_match_state = MatchState.ROUND_END
	_state_timer = 0.0
	_set_status("Round ended! %s wins" % winner_name)


func _start_intermission() -> void:
	_match_state = MatchState.INTERMISSION
	_state_timer = 0.0
	hud.show_intermission()
	Game.notify_intermission()
	_set_status("Intermission...")


func _reset_round() -> void:
	_spawn_i = [0, 0]
	_fill_bots()
	_start_round()


func _set_status(t: String) -> void:
	if menu:
		menu.set_status(t)
	print(t)
