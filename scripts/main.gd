extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DUMMY_SCENE := preload("res://scenes/dummy_target.tscn")
const SPAWNS := [
	Vector3(0.0, 0.0, 11.0),
	Vector3(7.0, 0.0, 11.0),
	Vector3(-7.0, 0.0, 11.0),
	Vector3(11.0, 0.0, 6.0),
	Vector3(-11.0, 0.0, 6.0),
]
const DUMMY_SPAWNS := [
	Vector3(0.0, 0.0, -6.0),
	Vector3(5.0, 0.0, -9.0),
	Vector3(-6.0, 0.0, -4.0),
]

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var dummies_root: Node3D = $Dummies
@onready var dummy_spawner: MultiplayerSpawner = $DummySpawner
@onready var hud: Hud = $CanvasLayer/Hud
@onready var menu: Control = $CanvasLayer/Menu

var _spawn_i := 0
var _status: Label
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _port_edit: LineEdit


func _ready() -> void:
	DisplayServer.window_set_title("Gevechtspel")
	if has_node("MenuCamera"):
		$MenuCamera.look_at(Vector3(0, 1, 0))
		$MenuCamera.current = true
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player_node
	dummy_spawner.spawn_path = NodePath("../Dummies")
	dummy_spawner.add_spawnable_scene("res://scenes/dummy_target.tscn")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Game.local_player_ready.connect(_on_local_player_ready)
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
	_spawn_player(multiplayer.get_unique_id())
	_spawn_dummies()


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
		return
	multiplayer.multiplayer_peer = peer
	Game.is_offline = false
	Game.is_dedicated = dedicated
	if dedicated:
		_enter_play()
		hud.visible = false
		DisplayServer.window_set_title("Gevechtspel server :%d" % port)
		print("Dedicated server on port ", port)
		_spawn_dummies()
		return
	_enter_play()
	_set_status("Hosting on port %d" % port)
	_spawn_player(1)
	_spawn_dummies()


func _connect_to_server() -> void:
	Game.player_name = _name_edit.text.strip_edges()
	if Game.player_name == "":
		Game.player_name = "Player"
	var ip := _ip_edit.text.strip_edges()
	var port := int(_port_edit.text)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_set_status("Connect failed to start (err %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	Game.is_offline = false
	Game.is_dedicated = false
	_set_status("Connecting to %s:%d …" % [ip, port])


func _on_connected_to_server() -> void:
	_enter_play()
	_set_status("Connected.")
	DisplayServer.window_set_title("Gevechtspel — %s" % Game.player_name)
	Game.submit_display_name.rpc_id(1, Game.player_name)


func _on_connection_failed() -> void:
	_set_status("Connection failed. Is the host running, and is the port free?")
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.visible = false
	Game.is_offline = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if has_node("MenuCamera"):
		$MenuCamera.current = true


func _on_server_disconnected() -> void:
	_set_status("Server left.")
	menu.visible = true
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.is_offline = true
	if has_node("MenuCamera"):
		$MenuCamera.current = true


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if id == 1:
		return
	_spawn_player(id)


func _on_peer_disconnected(id: int) -> void:
	Game.clear_peer_hp(id)
	var node := players_root.get_node_or_null(str(id))
	if node:
		node.queue_free()


func _spawn_player(peer_id: int) -> void:
	if players_root.get_node_or_null(str(peer_id)):
		return
	var pos: Vector3 = SPAWNS[_spawn_i % SPAWNS.size()]
	_spawn_i += 1
	var fallback := Game.player_name if peer_id == multiplayer.get_unique_id() else "Player"
	var n := Game.take_pending_name(peer_id, fallback)
	if Game.is_offline:
		var p: Player = _spawn_player_node({"id": peer_id, "pos": pos, "n": n})
		players_root.add_child(p, true)
		return
	if not multiplayer.is_server():
		return
	spawner.spawn({"id": peer_id, "pos": pos, "n": n})


func _spawn_player_node(data: Variant) -> Node:
	var d: Dictionary = data
	if typeof(d) != TYPE_DICTIONARY or not d.has("id"):
		push_error("Bad player spawn payload: %s" % str(data))
		return Node.new()
	var p: Player = PLAYER_SCENE.instantiate()
	var id := int(d["id"])
	p.peer_id = id
	p.name = str(id)
	p.display_name = str(d.get("n", "Player"))
	p.position = d["pos"]
	p.set_multiplayer_authority(id, true)
	Game.set_hp(p, Player.MAX_HP)
	return p


func _spawn_dummies() -> void:
	if dummies_root.get_child_count() > 0:
		return
	if Game.is_networked() and not multiplayer.is_server():
		return
	for i in DUMMY_SPAWNS.size():
		var dummy: DummyTarget = DUMMY_SCENE.instantiate()
		dummy.name = "Dummy%d" % (i + 1)
		dummy.position = DUMMY_SPAWNS[i]
		if Game.is_networked():
			dummy.set_multiplayer_authority(1, true)
		dummies_root.add_child(dummy, true)


func _on_local_player_ready(player: Player) -> void:
	_disable_menu_camera()
	player.make_active_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.bind_player(player)
	DisplayServer.window_set_title("Gevechtspel — %s" % Game.player_name)


func _set_status(t: String) -> void:
	if _status:
		_status.text = t
	print(t)
