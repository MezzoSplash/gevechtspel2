class_name MainMenu
extends Control
## Home / Singleplayer / Multiplayer / Settings. Main starts the session.

signal play_local_pressed
signal host_pressed
signal connect_pressed
signal start_match_pressed
signal lobby_leave_pressed
signal lobby_team_picked(team: int)

@onready var status_label: Label = $Center/Home/Status
@onready var solo_name: LineEdit = $Center/Solo/NameRow/NameEdit
@onready var mp_name: LineEdit = $Center/Mp/NameRow/NameEdit
@onready var ip_edit: LineEdit = $Center/Mp/JoinRow/IpEdit
@onready var port_edit: LineEdit = $Center/Mp/JoinRow/PortEdit
@onready var settings_panel = $Center/Settings/SettingsPanel

var _team := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Center/Home/SoloButton.pressed.connect(func() -> void: show_screen("solo"))
	$Center/Home/MpButton.pressed.connect(func() -> void: show_screen("mp"))
	$Center/Home/SettingsButton.pressed.connect(func() -> void: show_screen("settings"))
	$Center/Home/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$Center/Solo/PlayButton.pressed.connect(func() -> void: play_local_pressed.emit())
	$Center/Solo/BackButton.pressed.connect(func() -> void: show_screen("home"))
	$Center/Mp/HostButton.pressed.connect(func() -> void: host_pressed.emit())
	$Center/Mp/JoinRow/JoinButton.pressed.connect(func() -> void: connect_pressed.emit())
	$Center/Mp/BackButton.pressed.connect(func() -> void: show_screen("home"))
	$Center/Lobby/StartButton.pressed.connect(func() -> void: start_match_pressed.emit())
	$Center/Lobby/LeaveButton.pressed.connect(func() -> void: lobby_leave_pressed.emit())
	$Center/Lobby/TeamRow/BlueButton.pressed.connect(func() -> void: lobby_team_picked.emit(0))
	$Center/Lobby/TeamRow/OrangeButton.pressed.connect(func() -> void: lobby_team_picked.emit(1))
	$Center/Settings/BackButton.pressed.connect(func() -> void: show_screen("home"))
	$Center/Solo/TeamRow/BlueButton.pressed.connect(func() -> void: set_team(0))
	$Center/Solo/TeamRow/OrangeButton.pressed.connect(func() -> void: set_team(1))
	set_team(0)
	show_screen("home")


func show_screen(id: String) -> void:
	$Center/Home.visible = id == "home"
	$Center/Solo.visible = id == "solo"
	$Center/Mp.visible = id == "mp"
	$Center/Settings.visible = id == "settings"
	$Center/Lobby.visible = id == "lobby"
	if id == "solo":
		solo_name.text = mp_name.text
	elif id == "mp":
		mp_name.text = solo_name.text
	elif id == "settings" and settings_panel and settings_panel.has_method("refresh"):
		settings_panel.refresh()


func set_status(t: String) -> void:
	if status_label:
		status_label.text = t
	var mp_status := get_node_or_null("Center/Mp/Status") as Label
	if mp_status:
		mp_status.text = t


func player_name() -> String:
	if $Center/Solo.visible:
		return solo_name.text.strip_edges() if solo_name else "Player"
	return mp_name.text.strip_edges() if mp_name else "Player"


func host_ip() -> String:
	return ip_edit.text.strip_edges() if ip_edit else "127.0.0.1"


func host_port() -> int:
	return int(port_edit.text) if port_edit else Game.DEFAULT_PORT


func set_player_name(n: String) -> void:
	if solo_name:
		solo_name.text = n
	if mp_name:
		mp_name.text = n


func set_host_ip(ip: String) -> void:
	if ip_edit:
		ip_edit.text = ip


func set_host_port(port: int) -> void:
	if port_edit:
		port_edit.text = str(port)


func selected_team() -> int:
	return _team


func set_team(team: int) -> void:
	_team = clampi(team, 0, 1)
	Game.preferred_team = _team
	_paint_team_button($Center/Solo/TeamRow/BlueButton, _team == 0, Color(0.35, 0.55, 0.95))
	_paint_team_button($Center/Solo/TeamRow/OrangeButton, _team == 1, Color(0.92, 0.45, 0.28))
	if has_node("Center/Lobby/TeamRow/BlueButton"):
		_paint_team_button($Center/Lobby/TeamRow/BlueButton, _team == 0, Color(0.35, 0.55, 0.95))
		_paint_team_button($Center/Lobby/TeamRow/OrangeButton, _team == 1, Color(0.92, 0.45, 0.28))


func _paint_team_button(btn: Button, on: bool, col: Color) -> void:
	if btn == null:
		return
	btn.modulate = col if on else Color(0.55, 0.55, 0.58)


func refresh_lobby(lobby: Dictionary, is_host: bool) -> void:
	var blue := $Center/Lobby/Teams/BlueCol/List as Label
	var orange := $Center/Lobby/Teams/OrangeCol/List as Label
	var start_btn := $Center/Lobby/StartButton as Button
	if start_btn:
		start_btn.visible = is_host
	var blue_names: PackedStringArray = []
	var orange_names: PackedStringArray = []
	for id in lobby:
		var e: Dictionary = lobby[id]
		var n := str(e.get("name", "Player"))
		if int(id) == 1:
			n += "  (host)"
		if int(e.get("team", 0)) == 0:
			blue_names.append(n)
		else:
			orange_names.append(n)
	if blue:
		blue.text = "\n".join(blue_names) if blue_names.size() > 0 else "—"
	if orange:
		orange.text = "\n".join(orange_names) if orange_names.size() > 0 else "—"
	_paint_team_button($Center/Lobby/TeamRow/BlueButton, _team == 0, Color(0.35, 0.55, 0.95))
	_paint_team_button($Center/Lobby/TeamRow/OrangeButton, _team == 1, Color(0.92, 0.45, 0.28))
