class_name MainMenu
extends Control
## Home / Singleplayer / Multiplayer / Settings. Main starts the session.

signal play_local_pressed
signal host_pressed
signal connect_pressed
signal start_match_pressed
signal lobby_leave_pressed
signal lobby_team_picked(team: int)
signal match_choice_changed(map_id: StringName, mode: int)

@onready var status_label: Label = $Center/Home/Status
@onready var solo_name: LineEdit = $Center/Solo/NameRow/NameEdit
@onready var mp_name: LineEdit = $Center/Mp/NameRow/NameEdit
@onready var ip_edit: LineEdit = $Center/Mp/JoinRow/IpEdit
@onready var port_edit: LineEdit = $Center/Mp/JoinRow/PortEdit
@onready var settings_panel = $Center/Settings/SettingsPanel
@onready var version_label: Label = $VersionLabel

var _team := 0
var _applying_name := false
var class_editor: ClassEditor
var _map_opts: Array[OptionButton] = [] # Solo + Mp (host) pickers, kept in sync
var _mode_opts: Array[OptionButton] = []
var _kill_boxes: Array[SpinBox] = []
var _time_boxes: Array[SpinBox] = []
var _bot_boxes: Array[SpinBox] = []
var _map_blurbs: Array[Label] = []
var _lobby_info: Label
var _filling_match := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Top-right corner, part of the menu only: hidden with it in game (HUD, pause, killcam).
	version_label.text = version_text()
	version_label.visible = not version_label.text.is_empty()
	$Center/Home/SoloButton.pressed.connect(func() -> void: show_screen("solo"))
	$Center/Home/MpButton.pressed.connect(func() -> void: show_screen("mp"))
	$Center/Home/SettingsButton.pressed.connect(func() -> void: show_screen("settings"))
	$Center/Home/ClassesButton.pressed.connect(func() -> void: show_screen("classes"))
	class_editor = ClassEditor.new()
	class_editor.name = "Classes"
	class_editor.visible = false
	$Center.add_child(class_editor)
	class_editor.back_pressed.connect(func() -> void: show_screen("home"))
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
	_filling_match = true
	_build_match_rows($Center/Solo, $Center/Solo/TeamRow.get_index())
	_build_match_rows($Center/Mp, $Center/Mp/HostButton.get_index())
	_filling_match = false
	_lobby_info = Label.new()
	_lobby_info.name = "MatchInfo"
	_lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_info.add_theme_font_size_override("font_size", 18)
	_lobby_info.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	$Center/Lobby.add_child(_lobby_info)
	$Center/Lobby.move_child(_lobby_info, $Center/Lobby/Title.get_index() + 1)
	set_match_choice(Game.last_map, Game.last_mode)
	set_team(0)
	if solo_name:
		solo_name.max_length = Game.NAME_MAX
	if mp_name:
		mp_name.max_length = Game.NAME_MAX
	set_player_name(Game.player_name)
	if solo_name and not solo_name.text_changed.is_connected(_on_name_edited):
		solo_name.text_changed.connect(_on_name_edited)
		solo_name.focus_exited.connect(_commit_name_fields)
		solo_name.text_submitted.connect(func(_t: String) -> void: _commit_name_fields())
	if mp_name and not mp_name.text_changed.is_connected(_on_name_edited):
		mp_name.text_changed.connect(_on_name_edited)
		mp_name.focus_exited.connect(_commit_name_fields)
		mp_name.text_submitted.connect(func(_t: String) -> void: _commit_name_fields())
	if not Game.local_name_changed.is_connected(set_player_name):
		Game.local_name_changed.connect(set_player_name)
	show_screen("home")


## Map, mode, kills, time and bots (singleplayer, and host settings under Multiplayer).
## Built here so both screens share one list (Maps.ORDER) and stay in sync.
func _build_match_rows(screen: VBoxContainer, at: int) -> void:
	var map_opt := OptionButton.new()
	map_opt.name = "MapOption"
	map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in Maps.ORDER:
		map_opt.add_item(Maps.display_name(id))
	var mode_opt := OptionButton.new()
	mode_opt.name = "ModeOption"
	mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in Game.MODE_NAMES.size():
		mode_opt.add_item(Game.mode_name(m))
	var kill_box := _make_spin(Game.KILLS_MIN, Game.KILLS_MAX, 1, "")
	var time_box := _make_spin(Game.TIME_MIN_MINUTES, Game.TIME_MAX_MINUTES, 1, "min")
	var bot_box := _make_spin(0, Game.BOT_COUNT_MAX, 1, "")
	var blurb := Label.new()
	blurb.name = "MapBlurb"
	blurb.add_theme_font_size_override("font_size", 14)
	blurb.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rows: Array = [
		_labeled_row("MapRow", "Map", map_opt),
		_labeled_row("ModeRow", "Mode", mode_opt),
		_labeled_row("KillsRow", "Kills", kill_box),
		_labeled_row("TimeRow", "Time", time_box),
		_labeled_row("BotsRow", "Bots", bot_box),
		blurb,
	]
	for i in rows.size():
		screen.add_child(rows[i])
		screen.move_child(rows[i], at + i)
	_map_opts.append(map_opt)
	_mode_opts.append(mode_opt)
	_kill_boxes.append(kill_box)
	_time_boxes.append(time_box)
	_bot_boxes.append(bot_box)
	_map_blurbs.append(blurb)
	map_opt.item_selected.connect(func(_i: int) -> void: _on_choice_changed())
	mode_opt.item_selected.connect(func(_i: int) -> void: _on_mode_changed())
	kill_box.value_changed.connect(func(v: float) -> void: _on_spin_changed(_kill_boxes, v))
	time_box.value_changed.connect(func(v: float) -> void: _on_spin_changed(_time_boxes, v))
	bot_box.value_changed.connect(func(v: float) -> void: _on_spin_changed(_bot_boxes, v))


func _labeled_row(row_name: String, label_text: String, field: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	row.add_child(field)
	return row


func _make_spin(lo: float, hi: float, step: float, suffix: String) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = step
	box.rounded = true
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.select_all_on_focus = true
	if suffix != "":
		box.suffix = suffix
	return box


func _on_mode_changed() -> void:
	if _filling_match:
		return
	var mo := selected_mode()
	var old := Game.last_mode
	if mo != old and selected_kills() == Game.default_kills_for(old):
		_on_spin_changed(_kill_boxes, Game.default_kills_for(mo))
		return
	_on_choice_changed()


func _on_spin_changed(boxes: Array[SpinBox], v: float) -> void:
	if _filling_match:
		return
	_filling_match = true
	for b in boxes:
		b.set_value_no_signal(v)
	_filling_match = false
	_on_choice_changed()


func _on_choice_changed() -> void:
	if _filling_match:
		return
	Game.remember_match_choice(selected_map(), selected_mode(), selected_kills(), selected_time_min(), selected_bots())
	set_match_choice(selected_map(), selected_mode())
	match_choice_changed.emit(selected_map(), selected_mode())


func set_match_choice(map_id: StringName, mode: int) -> void:
	var mi := maxi(Maps.ORDER.find(map_id), 0)
	var mo := clampi(mode, Game.MODE_TDM, Game.MODE_FFA)
	_filling_match = true
	for o in _map_opts:
		o.select(mi)
	for o in _mode_opts:
		o.select(mo)
	for b in _kill_boxes:
		b.set_value_no_signal(Game.last_kills)
	for b in _time_boxes:
		b.set_value_no_signal(Game.last_time_min)
	for b in _bot_boxes:
		b.set_value_no_signal(Game.last_bots)
	_filling_match = false
	_refresh_match_blurb(mi, mo)
	$Center/Solo/TeamRow.visible = mo != Game.MODE_FFA


func _refresh_match_blurb(mi: int = -1, mo: int = -1) -> void:
	if mi < 0:
		mi = maxi(Maps.ORDER.find(selected_map()), 0)
	if mo < 0:
		mo = selected_mode()
	var info := Maps.info(Maps.ORDER[mi])
	var rule := "first to %d kills" % selected_kills()
	for b in _map_blurbs:
		b.text = "%s\n%s · %s or %d min · %d bots" % [
			info.blurb, Game.mode_name(mo), rule, selected_time_min(), selected_bots()
		]


func selected_map() -> StringName:
	if _map_opts.is_empty():
		return Maps.DEFAULT
	return Maps.ORDER[clampi(_map_opts[0].selected, 0, Maps.ORDER.size() - 1)]


func selected_mode() -> int:
	if _mode_opts.is_empty():
		return Game.MODE_TDM
	return clampi(_mode_opts[0].selected, Game.MODE_TDM, Game.MODE_FFA)


func selected_kills() -> int:
	if _kill_boxes.is_empty():
		return Game.last_kills
	return clampi(int(_kill_boxes[0].value), Game.KILLS_MIN, Game.KILLS_MAX)


func selected_time_min() -> int:
	if _time_boxes.is_empty():
		return Game.last_time_min
	return clampi(int(_time_boxes[0].value), Game.TIME_MIN_MINUTES, Game.TIME_MAX_MINUTES)


func selected_bots() -> int:
	if _bot_boxes.is_empty():
		return Game.last_bots
	return clampi(int(_bot_boxes[0].value), 0, Game.BOT_COUNT_MAX)


## Lobby header: what the server runs. FFA: one player list, no team buttons.
func set_lobby_match_info(map_id: StringName, mode: int) -> void:
	if _lobby_info:
		_lobby_info.text = "%s  ·  %s  ·  first to %d  ·  %d min" % [
			Maps.display_name(map_id), Game.mode_name(mode), Game.win_kills(), int(Game.round_time / 60.0)
		]
	var ffa := mode == Game.MODE_FFA
	$Center/Lobby/TeamRow.visible = not ffa
	$Center/Lobby/Teams/OrangeCol.visible = not ffa
	var head := $Center/Lobby/Teams/BlueCol/Head as Label
	head.text = "PLAYERS" if ffa else "BLUE"
	head.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92) if ffa else Color(0.35, 0.55, 0.95))
	($Center/Lobby/Hint as Label).text = (
		"Everyone vs everyone. Host starts the match." if ffa else "Pick a team. Host starts the match."
	)


func show_screen(id: String) -> void:
	$Center/Home.visible = id == "home"
	$Center/Solo.visible = id == "solo"
	$Center/Mp.visible = id == "mp"
	$Center/Settings.visible = id == "settings"
	$Center/Lobby.visible = id == "lobby"
	if class_editor:
		class_editor.visible = id == "classes"
		if id == "classes":
			class_editor.refresh()
	if id == "solo":
		solo_name.text = mp_name.text
	elif id == "mp":
		mp_name.text = solo_name.text
	elif id == "settings" and settings_panel and settings_panel.has_method("refresh"):
		settings_panel.refresh.call_deferred()


## "v0.2.15" from project.godot application/config/version: the one place the release bump sets
## the game version (export presets use the same number), so the menu cannot show a stale one.
static func version_text() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return "" if v.is_empty() else "v" + v


func set_status(t: String) -> void:
	if status_label:
		status_label.text = t
	var mp_status := get_node_or_null("Center/Mp/Status") as Label
	if mp_status:
		mp_status.text = t


## The saved profile name. The line edits write it on each change, so Play uses that, not a stale box.
func player_name() -> String:
	if Game.player_name.strip_edges() != "":
		return Game.player_name
	if $Center/Solo.visible and solo_name:
		return solo_name.text.strip_edges()
	return mp_name.text.strip_edges() if mp_name else "Player"


func host_ip() -> String:
	return ip_edit.text.strip_edges() if ip_edit else "127.0.0.1"


func host_port() -> int:
	return int(port_edit.text) if port_edit else Game.DEFAULT_PORT


## Fills both name boxes. A box that is being typed in keeps a trailing space until it loses focus.
func set_player_name(n: String) -> void:
	_apply_name_field(solo_name, n)
	_apply_name_field(mp_name, n)


func _apply_name_field(edit: LineEdit, n: String) -> void:
	if edit == null or edit.text == n:
		return
	if edit.has_focus() and Game.clean_name(edit.text) == n:
		return
	_applying_name = true
	edit.text = n
	_applying_name = false


func _on_name_edited(t: String) -> void:
	if _applying_name:
		return
	Game.set_player_name(t)


func _commit_name_fields() -> void:
	_applying_name = true
	if solo_name:
		solo_name.text = Game.player_name
	if mp_name:
		mp_name.text = Game.player_name
	_applying_name = false


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


## Two columns. Start is host-only. "(host)" is peer 1, not whoever created the listen server later.
func refresh_lobby(lobby: Dictionary, is_host: bool) -> void:
	var blue := $Center/Lobby/Teams/BlueCol/List as Label
	var orange := $Center/Lobby/Teams/OrangeCol/List as Label
	var start_btn := $Center/Lobby/StartButton as Button
	if start_btn:
		start_btn.visible = is_host
	set_lobby_match_info(Game.map_id, Game.mode)
	var blue_names: PackedStringArray = []
	var orange_names: PackedStringArray = []
	for id in lobby:
		var e: Dictionary = lobby[id]
		var n := str(e.get("name", "Player"))
		if int(id) == 1:
			n += "  (host)"
		if int(e.get("team", 0)) == 0 or Game.is_ffa():
			blue_names.append(n)
		else:
			orange_names.append(n)
	if blue:
		blue.text = "\n".join(blue_names) if blue_names.size() > 0 else "—"
	if orange:
		orange.text = "\n".join(orange_names) if orange_names.size() > 0 else "—"
	_paint_team_button($Center/Lobby/TeamRow/BlueButton, _team == 0, Color(0.35, 0.55, 0.95))
	_paint_team_button($Center/Lobby/TeamRow/OrangeButton, _team == 1, Color(0.92, 0.45, 0.28))
