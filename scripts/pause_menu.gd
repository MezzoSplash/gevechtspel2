extends Control
## Local overlay. Offline pauses the tree; LAN does not.

signal resume_pressed
signal leave_pressed
signal change_class_pressed

@onready var buttons: VBoxContainer = $Center/Buttons
@onready var settings_wrap: VBoxContainer = $SettingsWrap
@onready var settings_panel = $SettingsWrap/SettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Center/Buttons/ResumeButton.pressed.connect(func() -> void: resume_pressed.emit())
	$Center/Buttons/ClassButton.pressed.connect(func() -> void: change_class_pressed.emit())
	$Center/Buttons/SettingsButton.pressed.connect(_show_settings)
	$Center/Buttons/LeaveButton.pressed.connect(func() -> void: leave_pressed.emit())
	$Center/Buttons/QuitButton.pressed.connect(func() -> void: get_tree().quit())
	$SettingsWrap/BackButton.pressed.connect(_show_buttons)


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


func _show_settings() -> void:
	buttons.visible = false
	settings_wrap.visible = true
	# Next frame: OptionButton.clear during the show/layout pass SIGSEGVs Godot 4.7.
	if settings_panel and settings_panel.has_method("refresh"):
		settings_panel.refresh.call_deferred()
