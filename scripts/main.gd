extends Node3D
## Arena root: menu, match flow (warmup → play → final killcam → end → intermission), and pawn spawn.
## Server (or offline host) is the only one that creates players/bots.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
# Spawn points live per map in Maps (scripts/maps.gd). FFA: a point that was just handed out
# counts as occupied for this long, so pawns respawning together do not share one.
const FFA_RECENT_SPAWN := 2.0

enum MatchState { WARMUP, FREEZE, PLAYING, ROUND_END, INTERMISSION, KILLCAM }

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: Hud = $CanvasLayer/Hud
@onready var menu = $CanvasLayer/Menu
@onready var pause_ui = $CanvasLayer/Pause
@onready var world: Node3D = $World

var map_node: Node3D # the loaded map scene under World
var _loaded_map: StringName = &""
var _nav_baked_for: StringName = &""
var _recent_spawns: Array[Dictionary] = [] # FFA: {pos, t} handed out lately

var _leaving := false
var class_select: ClassSelect

var _spawn_i := [0, 0] # next spawn index per team
var _match_state := MatchState.WARMUP
var _state_timer := 0.0
var _bot_id_counter := -1 # bots use negative peer_ids: -1, -2, …
var _version_mismatch := "" # server's NET_VERSION when the auth step refused us
var _killcam_sent := false
## True while the home menu is up: the offline match clock then runs a bot-only background match.
## It loops on its own (no final killcam) and every Play / Host / Join tears it down first.
var _menu_match := true


func _ready() -> void:
	DisplayServer.window_set_title("Gevechtspel")
	Game.spawn_picker = _pick_respawn
	Game.match_config_handler = _on_match_config
	var args := _parse_args()
	# Menu backdrop: the map you played last (or the one the server CLI asks for).
	Game.map_id = args.map if args.map != &"" else Game.last_map
	Game.mode = int(args.mode) if int(args.mode) >= 0 else Game.last_mode
	_load_map(Game.map_id, false)
	if has_node("MenuCamera"):
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
	_setup_version_auth()
	Game.local_player_ready.connect(_on_local_player_ready)
	Game.round_ended.connect(_on_round_ended)
	Game.match_starting.connect(_on_match_starting)
	Game.lobby_changed.connect(_on_lobby_changed)
	menu.play_local_pressed.connect(_play_locally)
	menu.host_pressed.connect(_host_game)
	menu.connect_pressed.connect(_connect_to_server)
	menu.match_choice_changed.connect(_on_menu_match_choice)
	if menu.has_signal("start_match_pressed"):
		menu.start_match_pressed.connect(_start_match_from_lobby)
	if menu.has_signal("lobby_team_picked"):
		menu.lobby_team_picked.connect(_lobby_pick_team)
	if menu.has_signal("lobby_leave_pressed"):
		menu.lobby_leave_pressed.connect(_leave_to_menu)
	if pause_ui:
		pause_ui.resume_pressed.connect(_resume_game)
		pause_ui.leave_pressed.connect(_leave_to_menu)
		pause_ui.change_class_pressed.connect(_open_change_class)
	class_select = ClassSelect.new()
	class_select.name = "ClassSelect"
	$CanvasLayer.add_child(class_select)
	class_select.picked.connect(_on_class_picked)
	class_select.back_pressed.connect(_open_pause)
	Game.loadouts.loadout_applied.connect(_on_loadout_applied)
	if args.get("name", "") != "":
		Game.player_name = Game.clean_name(str(args["name"]))
		menu.set_player_name(Game.player_name)
	if args.get("server", false):
		_start_server(int(args.get("port", Game.DEFAULT_PORT)), true, Game.map_id, Game.mode)
		return
	if str(args.get("connect", "")) != "":
		menu.set_host_ip(str(args["connect"]))
		menu.set_host_port(int(args.get("port", Game.DEFAULT_PORT)))
		_connect_to_server()
		return
	menu.visible = true


## ENet auth step: both sides send NET_VERSION before the peer counts as connected.
## A mismatch never reaches the lobby or the RPCs (whose ids shift between versions).
func _setup_version_auth() -> void:
	var sm := multiplayer as SceneMultiplayer
	if sm == null:
		return
	sm.auth_callback = _on_auth_data
	sm.auth_timeout = 5.0
	sm.peer_authenticating.connect(_on_peer_authenticating)
	sm.peer_authentication_failed.connect(_on_peer_authentication_failed)


func _on_peer_authenticating(id: int) -> void:
	(multiplayer as SceneMultiplayer).send_auth(id, Game.NET_VERSION.to_utf8_buffer())


func _on_auth_data(id: int, data: PackedByteArray) -> void:
	var sm := multiplayer as SceneMultiplayer
	var theirs := data.get_string_from_utf8()
	if theirs == Game.NET_VERSION:
		sm.complete_auth(id)
		return
	print("NET: version mismatch with peer %d: theirs %s, ours %s" % [id, theirs, Game.NET_VERSION])
	if not multiplayer.is_server():
		_version_mismatch = theirs
	# Not right away: our own version packet must still reach them, so they can show the mismatch too.
	var link := multiplayer.multiplayer_peer
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer == link and link.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			sm.disconnect_peer(id)
	)


func _on_peer_authentication_failed(id: int) -> void:
	print("NET: authentication failed for peer %d" % id)
	if multiplayer.is_server():
		return
	var why := "Could not join: no version reply from the server (older build?)."
	if _version_mismatch != "":
		why = "Version mismatch: server %s, you %s." % [_version_mismatch, Game.NET_VERSION]
	_version_mismatch = ""
	# Deferred: swapping multiplayer_peer inside a SceneMultiplayer signal crashes the engine.
	call_deferred("_drop_to_menu", why)


func _drop_to_menu(status: String) -> void:
	_leave_to_menu()
	_set_status(status)


## Map scene under World. The old one goes at once (same node names, and no one may hit its
## colliders after this). Bots only run on the match authority, so only it bakes the navmesh.
func _load_map(id: StringName, bake: bool) -> void:
	if not Maps.has(id):
		id = Maps.DEFAULT
	if _loaded_map != id or map_node == null:
		if map_node:
			world.remove_child(map_node)
			map_node.free()
		var scene := load(str(Maps.info(id).scene)) as PackedScene
		map_node = scene.instantiate() as Node3D
		world.add_child(map_node)
		_loaded_map = id
		_nav_baked_for = &""
		if Game.impacts:
			Game.impacts.clear()
		var cam: Array = Maps.info(id).menu_cam
		if has_node("MenuCamera"):
			$MenuCamera.global_position = cam[0]
			$MenuCamera.look_at(cam[1])
		print("MAP: loaded %s" % Maps.display_name(id))
	if bake and _nav_baked_for != id:
		_nav_baked_for = id
		_bake_nav.call_deferred() # CSG builds its collision deferred after entering the tree


## Menu backdrop follows the map picker (not while a session or lobby is open).
func _on_menu_match_choice(id: StringName, _mode: int) -> void:
	if Game.is_offline and not Game.in_lobby and not hud.visible:
		if id != _loaded_map:
			_reset_match_state() # background bots must not stand on (or fall out of) the old map
		_load_map(id, false)


## Server/offline picks map+mode; clients get here through Game.sync_match_config.
func _on_match_config(id: StringName, mode: int) -> void:
	_load_map(id, Game._is_match_authority())
	if menu and menu.has_method("set_lobby_match_info"):
		menu.set_lobby_match_info(id, mode)
	print("MATCH: %s on %s" % [Game.mode_name(mode), Maps.display_name(id)])


## Runtime navmesh from arena collision (not GPU meshes).
func _bake_nav() -> void:
	if map_node == null:
		return
	var region := map_node.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var arena := map_node.get_node_or_null("Arena") as Node3D
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
	var out := {"server": false, "port": Game.DEFAULT_PORT, "connect": "", "name": "", "map": &"", "mode": -1}
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
			"--map":
				i += 1
				if i < args.size():
					out.map = Maps.parse(args[i])
					if out.map == &"":
						printerr("Unknown --map '%s'. Maps: %s" % [args[i], ", ".join(Maps.ORDER)])
			"--mode":
				i += 1
				if i < args.size():
					out.mode = Game.parse_mode(args[i])
					if out.mode < 0:
						printerr("Unknown --mode '%s'. Use tdm or ffa." % args[i])
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
	elif _match_state == MatchState.KILLCAM:
		_tick_killcam(delta)
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


## Locked since the round ended. After POST the replay starts everywhere; when it is over, unlock and
## go on with the normal round end (board, intermission, next round).
func _tick_killcam(delta: float) -> void:
	_state_timer += delta
	if not _killcam_sent and _state_timer >= Killcam.POST:
		_killcam_sent = true
		Game.killcam.play_final(Game.killcam_pick()) # best trickshot of the round, else the last kill
	if _state_timer >= Killcam.total_time():
		Game.killcam.set_lock(false)
		_match_state = MatchState.ROUND_END
		_state_timer = 0.0


func _tick_round_end(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= Game.ROUND_END_TIME:
		_start_intermission()


func _tick_intermission(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= Game.INTERMISSION_TIME:
		_reset_round()


## Server clock only. Clients get the freeze flag and count the 3 seconds on the HUD.
func _tick_freeze(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= Game.FREEZE_TIME:
		Game.end_freeze()
		_match_state = MatchState.PLAYING
		_state_timer = 0.0
		_match_status("Round started!")


func _start_round() -> void:
	_match_state = MatchState.FREEZE
	_state_timer = 0.0
	Game.start_round()
	_spawn_all_players()
	_fill_bots()
	Game.set_round_frozen(true)
	_match_status("Get ready")


func _spawn_all_players() -> void:
	_respawn_all_pawns()


## Clients own their pawn transforms — must RPC respawn, not only move the server copy.
func _respawn_all_pawns() -> void:
	for n in players_root.get_children():
		var p := n as Player
		if p == null:
			continue
		Game.respawn_pawn(p)


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


## Lobby closes on every peer. Only the server spawns humans and then the freeze.
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


## Host writes the roster directly. A client asks; the server echoes the new columns.
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
	_reset_match_state()
	_menu_match = false
	Game.is_offline = true
	Game.is_dedicated = false
	Game.player_name = Game.clean_name(menu.player_name())
	Game.preferred_team = menu.selected_team()
	Game.set_match_config(menu.selected_map(), menu.selected_mode())
	_enter_play()
	_match_state = MatchState.WARMUP
	_state_timer = 0.0
	_spawn_player(multiplayer.get_unique_id(), Game.preferred_team)
	_fill_bots()


func _host_game() -> void:
	Game.player_name = Game.clean_name(menu.player_name(), "Host")
	Game.preferred_team = menu.selected_team()
	_start_server(menu.host_port(), false, menu.selected_map(), menu.selected_mode())


func _start_server(port: int, dedicated: bool, map_id: StringName, mode: int) -> void:
	_reset_match_state()
	_menu_match = false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 10)
	if err != OK:
		_menu_match = true # still in the menu: the background match starts again
		_set_status("Could not host on port %d (err %d)" % [port, err])
		print("SERVER: create_server failed with err %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	Game.is_offline = false
	Game.is_dedicated = dedicated
	Game.set_match_config(map_id, mode)
	print("SERVER: Server started on port %d, dedicated=%s, %s on %s" % [
		port, dedicated, Game.mode_name(), Maps.display_name(Game.map_id)
	])
	if dedicated:
		Engine.max_fps = 60 # headless has no vsync; no need to spin a Pi core on menus/HUD
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
	_reset_match_state()
	_menu_match = false
	Game.player_name = Game.clean_name(menu.player_name())
	Game.preferred_team = menu.selected_team()
	var ip: String = menu.host_ip()
	var port: int = menu.host_port()
	print("CLIENT: Creating client peer for %s:%d" % [ip, port])
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_menu_match = true
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
	call_deferred("_reset_to_offline")
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
	call_deferred("_drop_to_menu", "Server left.")


## Failed connect: back to a valid offline peer (id 1), outside the multiplayer signal.
func _reset_to_offline() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_match_state()
	Game.is_offline = true
	_menu_match = true


## Late join: defer so MultiplayerSpawner can replicate existing pawns first.
func _on_peer_connected(id: int) -> void:
	print("SERVER: Peer connected: %d" % id)
	if not multiplayer.is_server():
		return
	if id == 1:
		return
	# Map + mode first, so the client loads the right arena before its pawn and the bots arrive.
	Game.sync_match_config.rpc_id(id, String(Game.map_id), Game.mode)
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


func _open_change_class() -> void:
	if pause_ui:
		pause_ui.hide_for_overlay()
	class_select.open_change()


## Back to the game either way; a mid-match pick only tells you when it lands.
func _on_class_picked(index: int, queued: bool) -> void:
	if pause_ui:
		pause_ui.close(hud.visible, false)
	elif hud.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if queued:
		hud.show_notice("Class changes at next spawn: %s" % Game.loadouts.class_name_at(index), 3.5)


func _on_loadout_applied(loadout: Dictionary, now: bool) -> void:
	if not now and hud.visible:
		hud.show_notice("Class: %s" % PlayerClasses.summary(loadout), 2.5)


func _resume_game() -> void:
	if pause_ui:
		pause_ui.close()


func _leave_to_menu() -> void:
	_leaving = true
	if pause_ui:
		pause_ui.close(false)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	# Not null: a null peer makes get_unique_id() 0 (+ an error every frame) and solo would spawn pawn "0".
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_match_state()
	Game.is_offline = true
	Game.is_dedicated = false
	_menu_match = true
	hud.visible = false
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	if menu.has_method("show_screen"):
		menu.show_screen("home")
	if has_node("MenuCamera"):
		$MenuCamera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_leaving = false


## Ends whatever match runs here, in any state (menu background match, a session being left):
## pawns, match clock, final killcam lock, round freeze, scores, grenades, HUD. Play, Host and Join
## all start from this, so a background round that was in its killcam, round end or intermission
## can never leave the real game locked (killcam_active) or stuck in an old state.
func _reset_match_state() -> void:
	if class_select:
		class_select.close_silently()
	get_tree().paused = false
	Game.pause_open = false
	Game.chat_open = false
	for c in players_root.get_children():
		players_root.remove_child(c) # gone at once: no team counts or names shared with the new pawns
		c.queue_free()
	Game.reset_session() # also ends a running killcam replay and clears killcam_active / round_frozen
	Game.stop_round_sting()
	_bot_id_counter = -1
	_spawn_i = [0, 0]
	_recent_spawns.clear()
	_match_state = MatchState.WARMUP
	_state_timer = 0.0
	_killcam_sent = false
	hud.reset_session()


func _on_peer_disconnected(id: int) -> void:
	if _leaving:
		return
	if Game.in_lobby:
		Game.remove_lobby_member(id)
		return
	# Clients only mirror: the spawner despawns the pawn and the server syncs the score removal.
	if not multiplayer.is_server():
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
	_spawn_bot(team)
	# Bots are not in the spawner's replication (Sync visibility off): send the new roster.
	broadcast_pawns.call_deferred()


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
	if Game.is_ffa():
		team = _team_for_human() # no teams in FFA; this only keeps the 5+5 bot fill even
	team = clampi(team, Game.TEAM_A, Game.TEAM_B)
	var pos := _next_spawn(team)
	var fallback: String = Game.player_name if peer_id == multiplayer.get_unique_id() else "Player"
	var n: String = Game.take_pending_name(peer_id, fallback)
	print("SERVER: Spawning player %d team %d at %s with name %s" % [peer_id, team, pos, n])
	_add_pawn({"id": peer_id, "pos": pos, "yaw": Maps.spawn_yaw(pos, team, Game.is_ffa()), "n": n, "bot": false, "team": team})


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
	Game.send_match_state(id)
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
			"weapon": String(p.weapon.def.id) if p.weapon and p.weapon.def else "rifle",
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
		elif p and not p.is_local():
			# Name/team are server-owned (not in the Synchronizer), so late joiners get them here.
			p.team_id = int(entry.get("team", p.team_id))
			p.set_display_name(str(entry.get("n", p.display_name)))
			p._apply_team_visual()
			if p.weapon:
				p.weapon.equip_remote(StringName(str(entry.get("weapon", "rifle"))))
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
	if d.has("yaw"):
		p.rotation.y = float(d["yaw"])
	elif p.team_id == Game.TEAM_B:
		p.rotation.y = PI # Orange spawns at -Z: face the street, not the back wall
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
	if Game.is_ffa():
		return _ffa_spawn(null)
	var list: Array = Maps.team_spawns(Game.map_id, team)
	var i: int = int(_spawn_i[team]) % list.size()
	_spawn_i[team] = i + 1
	return list[i]


## Game.respawn_pawn asks this for every respawn. TDM: the pawn's own team spawn (set when it
## spawned). FFA: a fresh point each time, as far as possible from everyone else.
func _pick_respawn(p: Player) -> Transform3D:
	if not Game.is_ffa():
		return p._spawn_xform
	var pos := _ffa_spawn(p)
	return Transform3D(Basis(Vector3.UP, Maps.spawn_yaw(pos, p.team_id, true)), pos)


## FFA spawn: the candidate whose nearest living other pawn (or a point handed out in the last
## FFA_RECENT_SPAWN s) is farthest away. A little jitter so equal spots do not always win in order.
func _ffa_spawn(for_pawn: Player) -> Vector3:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_recent_spawns.size() - 1, -1, -1):
		if now - float(_recent_spawns[i].t) > FFA_RECENT_SPAWN:
			_recent_spawns.remove_at(i)
	var others: Array[Vector3] = []
	for child in players_root.get_children():
		var o := child as Player
		if o == null or o == for_pawn or o.is_dead or o.is_queued_for_deletion():
			continue
		others.append(o.global_position if o.is_inside_tree() else o.position)
	for r in _recent_spawns:
		others.append(r.pos)
	var best := Vector3.ZERO
	var best_score := -INF
	for c in Maps.ffa_spawns(Game.map_id):
		var cv: Vector3 = c
		var nearest := 1000.0
		for o in others:
			nearest = minf(nearest, cv.distance_to(o))
		var score := nearest + randf() * 1.5
		if score > best_score:
			best_score = score
			best = c
	_recent_spawns.append({"pos": best, "t": now})
	return best


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


## loadout = abs(id) % 6 → armory index: rifle / pistol / shotgun / sniper / smg / revolver.
func _spawn_bot(team: int) -> void:
	if Game.is_networked() and not multiplayer.is_server():
		return
	var id := _bot_id_counter
	_bot_id_counter -= 1
	var pos := _next_spawn(team)
	_add_pawn({
		"id": id,
		"pos": pos,
		"yaw": Maps.spawn_yaw(pos, team, Game.is_ffa()),
		"n": "Bot %d" % abs(id),
		"bot": true,
		"team": team,
		"loadout": abs(id) % Weapon.LOADOUT.size(),
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
			Game.net_hp.erase(bot.peer_id)
			Game.drop_score(bot.peer_id)
			bot.queue_free()


func _on_local_player_ready(player: Player) -> void:
	# Late join / dedicated server: we opened the lobby on connect, but the match is already running.
	if Game.in_lobby or menu.visible:
		Game.in_lobby = false
		_enter_play()
	_disable_menu_camera()
	player.make_active_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.bind_player(player)
	DisplayServer.window_set_title("Gevechtspel — %s" % Game.player_name)
	# First spawn of this session: pick a class (auto-assigns after ClassSelect.AUTO_TIME).
	if not Game.loadouts.picked_once and not class_select.is_open():
		class_select.open_initial()


## Clients only mirror the state. The match authority plays the final killcam first, if the round had a kill.
func _on_round_ended(_winner_peer_id: int, winner_name: String, _scores: Dictionary) -> void:
	_match_state = MatchState.ROUND_END
	_state_timer = 0.0
	_match_status("Round ended! %s wins" % winner_name)
	# The menu's background match skips the replay (it would take the camera) and just loops.
	if Game._is_match_authority() and not Game.final_kill.is_empty() and not _menu_match:
		_match_state = MatchState.KILLCAM
		_killcam_sent = false
		Game.killcam.set_lock(true)


func _start_intermission() -> void:
	_match_state = MatchState.INTERMISSION
	_state_timer = 0.0
	hud.show_intermission()
	Game.notify_intermission()
	_match_status("Intermission...")


func _reset_round() -> void:
	_spawn_i = [0, 0]
	_fill_bots()
	_start_round()


## Match clock messages. The menu's background match keeps them out of the menu status line.
func _match_status(t: String) -> void:
	if not _menu_match:
		_set_status(t)


func _set_status(t: String) -> void:
	if menu:
		menu.set_status(t)
	print(t)
