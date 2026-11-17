extends Control
## Local overlay. Offline pauses the tree; LAN does not.

signal resume_pressed
signal leave_pressed
signal change_class_pressed

@onready var buttons: VBoxContainer = $Center/Buttons
@onready var settings_wrap: VBoxContainer = $SettingsWrap
@onready var settings_panel = $SettingsWrap/SettingsPanel
var _score: HBoxContainer
var _score_left: PanelContainer
var _score_clock: PanelContainer
var _score_right: PanelContainer
var _score_t := 0.0
var _footer: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Center/Buttons/ResumeButton.pressed.connect(func() -> void: resume_pressed.emit())
	$Center/Buttons/ClassButton.pressed.connect(func() -> void: change_class_pressed.emit())
	$Center/Buttons/SettingsButton.pressed.connect(_show_settings)
	$Center/Buttons/LeaveButton.pressed.connect(func() -> void: leave_pressed.emit())
	$Center/Buttons/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$SettingsWrap/BackButton.pressed.connect(_show_buttons)
	_crystal()


## Crystal layout (docs/ui-crystal/mockups/pause.png): the score as three floating shards above a
## centred column of cut buttons, red seams on leave/quit, the key hints as a footer shard.
func _crystal() -> void:
	var title := $Center/Buttons/Title as Label
	title.text = "PAUSED"
	title.add_theme_font_override("font", CrystalUi.caps_font())
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", CrystalStyle.ICE)
	_score = HBoxContainer.new()
	_score.name = "Score"
	_score.alignment = BoxContainer.ALIGNMENT_CENTER
	_score.add_theme_constant_override("separation", 6)
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_left = CrystalUi.score_shard(Vector4(18, 8, 22, 6), 3)
	_score_clock = CrystalUi.score_shard(Vector4(10, 10, 12, 12), 5, true)
	_score_right = CrystalUi.score_shard(Vector4(8, 18, 6, 22), 8)
	for p in [_score_left, _score_clock, _score_right]:
		_score.add_child(p)
	_score_left.custom_minimum_size = Vector2(200, 0)
	_score_right.custom_minimum_size = Vector2(200, 0)
	_score_clock.custom_minimum_size = Vector2(170, 0)
	buttons.add_child(_score)
	buttons.move_child(_score, title.get_index() + 1)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(gap)
	buttons.move_child(gap, _score.get_index() + 1)
	var list := [$Center/Buttons/ResumeButton, $Center/Buttons/ClassButton, $Center/Buttons/SettingsButton,
		$Center/Buttons/LeaveButton, $Center/Buttons/QuitButton]
	for i in list.size():
		var b := list[i] as Button
		b.theme_type_variation = &"MenuButtonBig"
		b.text = b.text.to_upper()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 58 if i == 0 else 50
	CrystalUi.button_hint($Center/Buttons/ResumeButton, "ESC")
	CrystalUi.stagger(list, [420, 380, 350, 320, 270], true)
	CrystalUi.seam_color($Center/Buttons/LeaveButton, CrystalUi.DANGER)
	CrystalUi.seam_color($Center/Buttons/QuitButton, CrystalUi.DANGER)
	var foot := CenterContainer.new()
	foot.name = "Footer"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -84
	foot.offset_bottom = -40
	var hint := Label.new()
	hint.text = "↑ ↓  choose   ·   enter  confirm   ·   esc  resume"
	foot.add_child(hint)
	add_child(foot)
	CrystalUi.footer(hint)
	_footer = foot
	var back := $SettingsWrap/BackButton as Button
	back.theme_type_variation = &"PrimaryButton"
	back.text = "‹  BACK"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size = Vector2(160, 44)


## Team modes: the two team scores in their colours around the clock. FFA: you against the
## leader. Uses the same scores the HUD shows (Game.team_score / player_score).
func refresh_score() -> void:
	if _score == null:
		return
	var t := Game.get_round_time_left()
	CrystalUi.set_score(_score_clock, "%d:%02d" % [int(t / 60.0), int(t) % 60], Game.mode_short_name().to_upper())
	if Game.is_ffa():
		var me := Game.player_score(multiplayer.get_unique_id())
		var best := 0
		for id in Game.scores:
			best = maxi(best, Game.player_score(id))
		CrystalUi.set_score(_score_left, str(me), "YOU", CrystalStyle.ICE)
		CrystalUi.set_score(_score_right, str(best), "LEADER", Color(CrystalStyle.ICE, 0.5))
	else:
		CrystalUi.set_score(_score_left, str(Game.team_score(0)), "", Player.team_color(0))
		CrystalUi.set_score(_score_right, str(Game.team_score(1)), "", Player.team_color(1))


func _process(delta: float) -> void:
	if not visible or not buttons.visible:
		return
	_score_t -= delta
	if _score_t <= 0.0:
		_score_t = 0.25
		refresh_score()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("toggle_mouse"):
		resume_pressed.emit()
		get_viewport().set_input_as_handled()


## Offline freezes the tree. A listen server must keep simulating for everyone else.
func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_show_buttons()
	if Game.is_offline:
		get_tree().paused = true
	Game.pause_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## release_input=false: an overlay that replaced this menu (class select) clears Game.pause_open itself.
func close(capture_mouse: bool = true, release_input: bool = true) -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	if release_input:
		Game.pause_open = false
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Change class: the picker draws instead of this menu; offline stays paused meanwhile.
func hide_for_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _show_buttons() -> void:
	buttons.visible = true
	settings_wrap.visible = false
	if _footer:
		_footer.visible = true
	refresh_score()
	# Keyboard / pad: start on Resume so Enter or A works straight away.
	($Center/Buttons/ResumeButton as Control).grab_focus.call_deferred()


func _show_settings() -> void:
	buttons.visible = false
	settings_wrap.visible = true
	if _footer:
		_footer.visible = false
	# Next frame: OptionButton.clear during the show/layout pass SIGSEGVs Godot 4.7.
	if settings_panel and settings_panel.has_method("refresh"):
		settings_panel.refresh.call_deferred()
	($SettingsWrap/BackButton as Control).grab_focus.call_deferred()
