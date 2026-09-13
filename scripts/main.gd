extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const TEAM_A_SPAWNS := [
	Vector3(0.0, 0.0, 18.0),
	Vector3(6.0, 0.0, 18.0),
	Vector3(-6.0, 0.0, 18.0),
	Vector3(11.0, 0.0, 14.0),
	Vector3(-11.0, 0.0, 14.0),
]
const TEAM_B_SPAWNS := [
	Vector3(0.0, 0.0, -18.0),
	Vector3(6.0, 0.0, -18.0),
	Vector3(-6.0, 0.0, -18.0),
	Vector3(11.0, 0.0, -14.0),
	Vector3(-11.0, 0.0, -14.0),
]

enum MatchState { WARMUP, PLAYING, ROUND_END, INTERMISSION }

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: Hud = $CanvasLayer/Hud
@onready var menu: Control = $CanvasLayer/Menu

var _spawn_i := [0, 0]
var _status: Label
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _match_state := MatchState.WARMUP
var _state_timer := 0.0
var _bot_id_counter := -1


func _ready() -> void:
	DisplayServer.window_set_title("Gevechtspel")
	if has_node("MenuCamera"):
		$MenuCamera.look_at(Vector3(0, 1, 0))
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
	call_deferred("_bake_nav")
	_build_menu()
	var args := _parse_args()
	if args.get("name", "") != "":
		Game.player_name = args["name"]
		_name_edit.text = Game.player_name
	if args.get("server", false):
		_start_server(int(args.get("port", Game.DEFAULT_PORT)), true)
		return
	if str(args.get("connect", "")) != "":
		_ip_edit.text = str(args["connect"])
		_port_edit.text = str(args.get("port", Game.DEFAULT_PORT))
		_connect_to_server()
		return
	menu.visible = true


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


func _process(delta: float) -> void:
	if not multiplayer.is_server() and not Game.is_offline:
		return
	if _match_state == MatchState.WARMUP:
		_tick_warmup(delta)
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


func _start_round() -> void:
	_match_state = MatchState.PLAYING
	_state_timer = 0.0
	Game.start_round()
	_spawn_all_players()
	_fill_bots()
	_set_status("Round started!")


func _spawn_all_players() -> void:
	for n in players_root.get_children():
		var p := n as Player
		if p:
			p.apply_respawn_state()


func _build_menu() -> void:
	var root := menu
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	for c in root.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.06, 0.08, 0.82)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(420, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var title := Label.new()
	title.text = "GEVECHTSPEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	col.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.text = "Play locally, or host / join a server."
	col.add_child(_status)
	var play_btn := Button.new()
	play_btn.text = "Play locally"
	play_btn.pressed.connect(_play_locally)
	col.add_child(play_btn)
	col.add_child(_labeled_edit("Name", "Player", true))
	col.add_child(_labeled_edit("IP", "127.0.0.1", false))
	col.add_child(_labeled_edit("Port", str(Game.DEFAULT_PORT), false))
	var host_btn := Button.new()
	host_btn.text = "Host game"
	host_btn.pressed.connect(_host_game)
	col.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.text = "Connect"
	join_btn.pressed.connect(_connect_to_server)
	col.add_child(join_btn)
	var hint := Label.new()
	hint.text = "Host on this PC, then a friend Connects to your IP.\nTwo local windows: Host in one, Connect 127.0.0.1 in the other."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)


func _labeled_edit(label: String, value: String, is_name: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(edit)
	if is_name:
		_name_edit = edit
	elif label == "IP":
		_ip_edit = edit
	else:
		_port_edit = edit
	return row


func _enter_play() -> void:
	menu.visible = false
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()
	hud.visible = true
	_disable_menu_camera()


func _disable_menu_camera() -> void:
	if has_node("MenuCamera"):
		$MenuCamera.current = false


func _play_locally() -> void:
	Game.is_offline = true
	Game.is_dedicated = false
	Game.player_name = _name_edit.text.strip_edges()
	if Game.player_name == "":
		Game.player_name = "Player"
	_enter_play()
	_match_state = MatchState.WARMUP
	_state_timer = 0.0
	_spawn_player(multiplayer.get_unique_id())
	_fill_bots()


func _host_game() -> void:
	Game.player_name = _name_edit.text.strip_edges()
	if Game.player_name == "":
		Game.player_name = "Host"
	_start_server(int(_port_edit.text), false)


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
	_enter_play()
	_match_state = MatchState.WARMUP
	_state_timer = 0.0
	_set_status("Hosting on port %d" % port)
	_spawn_player(1)
	_fill_bots()


func _connect_to_server() -> void:
	Game.player_name = _name_edit.text.strip_edges()
	if Game.player_name == "":
		Game.player_name = "Player"
	var ip := _ip_edit.text.strip_edges()
	var port := int(_port_edit.text)
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
	_enter_play()
	_set_status("Connected.")
	DisplayServer.window_set_title("Gevechtspel — %s" % Game.player_name)
	Game.submit_display_name.rpc_id(1, Game.player_name)


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
	_set_status("Server left.")
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.is_offline = true
	if has_node("MenuCamera"):
		$MenuCamera.current = true


func _on_peer_connected(id: int) -> void:
	print("SERVER: Peer connected: %d" % id)
	if not multiplayer.is_server():
		return
	if id == 1:
		return
	call_deferred("_finish_peer_join", id)


func _on_peer_disconnected(id: int) -> void:
	print("SERVER: Peer disconnected: %d" % id)
	var team := 0
	var node := players_root.get_node_or_null(str(id))
	if node is Player:
		team = (node as Player).team_id
		node.queue_free()
	Game.clear_peer_hp(id)
	Game.scores.erase(id)
	_spawn_bot(team)


func _spawn_player(peer_id: int, team: int = -1) -> void:
	print("SERVER: _spawn_player called for peer %d" % peer_id)
	if players_root.get_node_or_null(str(peer_id)):
		print("SERVER: Player %d already exists" % peer_id)
		return
	if team < 0:
		team = _team_for_human()
	var pos := _next_spawn(team)
	var fallback: String = Game.player_name if peer_id == multiplayer.get_unique_id() else "Player"
	var n: String = Game.take_pending_name(peer_id, fallback)
	print("SERVER: Spawning player %d team %d at %s with name %s" % [peer_id, team, pos, n])
	_add_pawn({"id": peer_id, "pos": pos, "n": n, "bot": false, "team": team})


func _finish_peer_join(id: int) -> void:
	if not multiplayer.is_server():
		return
	_spawn_player(id)
	_trim_bots()
	var scores_arr := Game.get_scores()
	if scores_arr.size() > 0:
		Game.sync_all_scores.rpc_id(id, scores_arr)
	Game.broadcast_roster()
	get_tree().create_timer(0.3).timeout.connect(Game.broadcast_roster)
	get_tree().create_timer(1.0).timeout.connect(Game.broadcast_roster)


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


func _team_for_human() -> int:
	if _human_count(Game.TEAM_A) <= _human_count(Game.TEAM_B):
		return Game.TEAM_A
	return Game.TEAM_B


func _smaller_team() -> int:
	if _team_count(Game.TEAM_A) <= _team_count(Game.TEAM_B):
		return Game.TEAM_A
	return Game.TEAM_B


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
	_set_status("Intermission...")


func _reset_round() -> void:
	_match_state = MatchState.WARMUP
	_state_timer = 0.0
	_spawn_i = [0, 0]
	for n in players_root.get_children():
		var p := n as Player
		if p:
			p.apply_respawn_state()
	_fill_bots()
	_set_status("Warmup...")


func _set_status(t: String) -> void:
	if _status:
		_status.text = t
	print(t)
