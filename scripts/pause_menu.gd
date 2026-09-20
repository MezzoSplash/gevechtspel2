extends Control
## Local overlay. Offline pauses the tree; LAN does not.

signal resume_pressed
signal leave_pressed

@onready var buttons: VBoxContainer = $Center/Buttons
@onready var settings_wrap: VBoxContainer = $Center/SettingsWrap
@onready var settings_panel = $Center/SettingsWrap/SettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Center/Buttons/ResumeButton.pressed.connect(func() -> void: resume_pressed.emit())
	$Center/Buttons/SettingsButton.pressed.connect(_show_settings)
	$Center/Buttons/LeaveButton.pressed.connect(func() -> void: leave_pressed.emit())
	$Center/Buttons/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$Center/SettingsWrap/BackButton.pressed.connect(_show_buttons)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("toggle_mouse"):
		resume_pressed.emit()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_show_buttons()
	if Game.is_offline:
		get_tree().paused = true
	Game.pause_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close(capture_mouse: bool = true) -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	Game.pause_open = false
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_buttons() -> void:
	buttons.visible = true
	settings_wrap.visible = false


func _show_settings() -> void:
	buttons.visible = false
	settings_wrap.visible = true
	if settings_panel and settings_panel.has_method("refresh"):
		settings_panel.refresh()
