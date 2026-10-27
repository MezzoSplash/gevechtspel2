extends ScrollContainer
## Tabs: Game, Graphics, Controls, Audio, HUD, Access. Writes user://settings.cfg through Game.
## Used in the main menu and the pause menu. Built in code so both stay the same screen.

const _LABEL_W := 130.0
const _SECTION := Color(1.0, 0.72, 0.22)
const _HINT := Color(0.7, 0.74, 0.8)

var _name_edit: LineEdit
var _window_opt: OptionButton
var _res_opt: OptionButton
var _res_sizes: Array[Vector2i] = []
var _vsync: CheckBox
var _fps: HSlider
var _fps_val: Label
var _fov: HSlider
var _fov_val: Label
var _scale: HSlider
var _scale_val: Label
var _msaa: OptionButton
var _quality: OptionButton
var _sway: OptionButton
var _sens: Array = [] # [HSlider, SpinBox]
var _ads: Array = []
var _invert: CheckBox
var _master: HSlider
var _master_val: Label
var _sfx: HSlider
var _sfx_val: Label
var _enemies: HSlider
var _enemies_val: Label
var _show_fps: CheckBox
var _music: HSlider
var _music_val: Label
var _ui: HSlider
var _ui_val: Label
var _shadows: OptionButton
var _xh_color: OptionButton
var _xh_style: OptionButton
var _xh_size: HSlider
var _xh_size_val: Label
var _minimap: CheckBox
var _killfeed: CheckBox
var _colorblind: OptionButton
var _shake: CheckBox
var _bind_buttons: Dictionary = {} # action -> Button
var _bind_note: Label
var _waiting_action := "" # rebind: next key / mouse button goes here
var _tab_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
const _TABS := ["Game", "Graphics", "Controls", "Audio", "HUD", "Access"]
var _filling := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	custom_minimum_size.x = 520
	($Body as Control).custom_minimum_size.x = 500
	if theme == null:
		theme = load("res://ui/menu_theme.tres") as Theme
	_build()
	refresh()
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_fit_height.call_deferred()
	)
	get_viewport().size_changed.connect(_fit_height)
	_fit_height.call_deferred()
	if not Game.local_name_changed.is_connected(_on_saved_name):
		Game.local_name_changed.connect(_on_saved_name)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		var vp := get_viewport()
		if vp and vp.size_changed.is_connected(_fit_height):
			vp.size_changed.disconnect(_fit_height)


## Tall enough to scroll on a 720p window, short enough that Back stays on screen.
func _fit_height() -> void:
	if not is_inside_tree():
		return
	var want := ($Body as Control).get_combined_minimum_size().y
	# Hidden on the first frame the minimum can still be 0. A floor keeps the list from collapsing.
	if want < 40.0:
		want = 480.0
	var avail := get_viewport().get_visible_rect().size.y - 210.0
	var h := minf(want, maxf(avail, 280.0))
	custom_minimum_size.y = h
	custom_maximum_size = Vector2(520.0, h)


func refresh() -> void:
	if _name_edit == null:
		return
	_filling = true
	if not _name_edit.has_focus():
		_name_edit.text = Game.player_name
	_select_quiet(_window_opt, clampi(Game.window_mode, 0, 2))
	_fill_resolutions()
	_vsync.set_pressed_no_signal(Game.vsync)
	_fps.set_value_no_signal(Game.max_fps)
	_fps_val.text = _fps_text(Game.max_fps)
	_fov.set_value_no_signal(Game.fov)
	_fov_val.text = "%d" % roundi(Game.fov)
	_scale.set_value_no_signal(Game.render_scale * 100.0)
	_scale_val.text = "%d%%" % roundi(Game.render_scale * 100.0)
	_select_quiet(_msaa, clampi(Game.msaa, 0, 3))
	_select_quiet(_quality, clampi(Game.gfx_quality, 0, 2))
	_select_quiet(_sway, clampi(Game.view_sway, 0, 2))
	_set_pair(_sens, Game.mouse_sens)
	_set_pair(_ads, Game.ads_sens)
	_invert.set_pressed_no_signal(Game.invert_y)
	_master.set_value_no_signal(Game.master_vol * 100.0)
	_sfx.set_value_no_signal(Game.sfx_vol * 100.0)
	_enemies.set_value_no_signal(Game.enemies_vol * 100.0)
	_show_fps.set_pressed_no_signal(Game.show_fps)
	_music.set_value_no_signal(Game.music_vol * 100.0)
	_ui.set_value_no_signal(Game.ui_vol * 100.0)
	_select_quiet(_shadows, Game.shadow_quality)
	_select_quiet(_xh_color, Game.crosshair_color)
	_select_quiet(_xh_style, Game.crosshair_style)
	_xh_size.set_value_no_signal(Game.crosshair_size * 100.0)
	_xh_size_val.text = "%d%%" % roundi(Game.crosshair_size * 100.0)
	_minimap.set_pressed_no_signal(Game.show_minimap)
	_killfeed.set_pressed_no_signal(Game.show_killfeed)
	_select_quiet(_colorblind, Game.colorblind)
	_shake.set_pressed_no_signal(Game.reduce_shake)
	_refresh_bindings()
	_refresh_audio_labels()
	_filling = false
	_fit_height()


func _build() -> void:
	var root := $Body
	_title(root)
	var bar := GridContainer.new() # 3 × 2 so six tabs fit the 500 px column
	bar.columns = 3
	bar.add_theme_constant_override("h_separation", 4)
	bar.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	root.add_child(bar)
	for i in _TABS.size():
		var b := Button.new()
		b.text = _TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_tab.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		root.add_child(page)
		_pages.append(page)

	var body := _pages[0] # Game
	_section(body, "NAME")
	_name_edit = _line_edit(_row(body, "Name"))
	_name_edit.placeholder_text = "Player"
	_name_edit.max_length = Game.NAME_MAX
	_name_edit.text_changed.connect(_on_name)
	_name_edit.focus_exited.connect(_commit_name)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_section(body, "VIEW")
	_sway = _options(_row(body, "Weapon sway"), ["Off", "Reduced", "Full"])
	_sway.item_selected.connect(_on_sway)

	body = _pages[1] # Graphics
	_section(body, "DISPLAY")
	_window_opt = _options(_row(body, "Window"), ["Windowed", "Borderless", "Fullscreen"])
	_window_opt.item_selected.connect(_on_window_mode)
	_res_opt = _options(_row(body, "Resolution"), [])
	_res_opt.item_selected.connect(_on_resolution)
	_vsync = _check(_row(body, "VSync"))
	_vsync.toggled.connect(_on_vsync)
	var fps_row := _row(body, "Max FPS")
	_fps = _slider(fps_row, 0, Game.FPS_CAP_MAX, 10)
	_fps_val = _value_label(fps_row)
	_fps.value_changed.connect(_on_fps)
	var fov_row := _row(body, "FOV")
	_fov = _slider(fov_row, Game.FOV_MIN, Game.FOV_MAX, 1)
	_fov_val = _value_label(fov_row)
	_fov.value_changed.connect(_on_fov)
	_section(body, "QUALITY")
	var scale_row := _row(body, "Render scale")
	_scale = _slider(scale_row, 50, 100, 5)
	_scale_val = _value_label(scale_row)
	_scale.value_changed.connect(_on_scale)
	_msaa = _options(_row(body, "Antialiasing"), ["Off", "2×", "4×", "8×"])
	_msaa.item_selected.connect(_on_msaa)
	_quality = _options(_row(body, "Graphics"), Gfx.NAMES)
	_quality.item_selected.connect(_on_quality)
	_shadows = _options(_row(body, "Shadows"), Game.SHADOW_NAMES)
	_shadows.item_selected.connect(func(i: int) -> void:
		if not _filling:
			Game.set_shadow_quality(i)
	)
	_hint(body, "VSync follows the monitor. Max FPS is an extra cap; Unlimited means no cap. Borderless uses the monitor's resolution. Render scale changes the 3D image only. Graphics Low drops SSAO, glow, fog and wall detail for the most FPS. Shadows Auto follows Graphics.")

	body = _pages[2] # Controls
	_section(body, "MOUSE")
	_sens = _number_row(body, "Mouse", Game.MOUSE_SENS_MIN, Game.MOUSE_SENS_MAX, 0.05, Game.set_mouse_sens)
	_ads = _number_row(body, "Aim / scope", Game.ADS_SENS_MIN, Game.ADS_SENS_MAX, 0.05, Game.set_ads_sens)
	_invert = _check(_row(body, "Invert Y"))
	_invert.toggled.connect(_on_invert)
	_hint(body, "Mouse: 1.00 = default. Aim / scope multiplies it while aiming (default 0.45).")
	_section(body, "KEYS")
	for pair in Game.REBIND_ACTIONS:
		var action: String = pair[0]
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_start_rebind.bind(action))
		_row(body, pair[1]).add_child(b)
		_bind_buttons[action] = b
	var reset := Button.new()
	reset.text = "Reset keys to default"
	reset.pressed.connect(func() -> void:
		_waiting_action = ""
		Game.reset_bindings()
		_bind_note.text = "Keys reset to default."
		_refresh_bindings()
	)
	body.add_child(reset)
	_bind_note = Label.new()
	_bind_note.theme_type_variation = &"HintLabel"
	_bind_note.add_theme_color_override("font_color", _HINT)
	_bind_note.text = "Click a key, then press the new key or mouse button. Esc cancels. A key already in use swaps places."
	_bind_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bind_note.custom_minimum_size = Vector2(500, 0)
	body.add_child(_bind_note)

	body = _pages[3] # Audio
	_section(body, "VOLUME")
	var master_row := _row(body, "Master")
	_master = _slider(master_row, 0, 100, 1)
	_master_val = _value_label(master_row)
	_master.value_changed.connect(_on_master)
	var sfx_row := _row(body, "Effects")
	_sfx = _slider(sfx_row, 0, 100, 1)
	_sfx_val = _value_label(sfx_row)
	_sfx.value_changed.connect(_on_sfx)
	var en_row := _row(body, "Enemies")
	_enemies = _slider(en_row, 0, roundi(Game.ENEMIES_VOL_MAX * 100.0), 1)
	_enemies_val = _value_label(en_row)
	_enemies.value_changed.connect(func(v: float) -> void:
		if not _filling:
			Game.set_enemies_vol(v / 100.0)
			_refresh_audio_labels()
	)
	var music_row := _row(body, "Music")
	_music = _slider(music_row, 0, 100, 1)
	_music_val = _value_label(music_row)
	_music.value_changed.connect(func(v: float) -> void:
		if not _filling:
			Game.set_music_vol(v / 100.0)
			_refresh_audio_labels()
	)
	var ui_row := _row(body, "UI")
	_ui = _slider(ui_row, 0, 100, 1)
	_ui_val = _value_label(ui_row)
	_ui.value_changed.connect(func(v: float) -> void:
		if not _filling:
			Game.set_ui_vol(v / 100.0)
			_refresh_audio_labels()
	)
	_hint(body, "Effects: guns, steps, explosions. Enemies: enemy shots, steps and reloads on top of Effects (100% = as loud as yours). Music: round start. UI: hit markers, announcer, killcam.")

	body = _pages[4] # HUD
	_section(body, "CROSSHAIR")
	_xh_color = _options(_row(body, "Colour"), Game.CROSSHAIR_COLOR_NAMES)
	_xh_style = _options(_row(body, "Style"), Game.CROSSHAIR_STYLES)
	var xs_row := _row(body, "Size")
	_xh_size = _slider(xs_row, 50, 200, 10)
	_xh_size_val = _value_label(xs_row)
	_xh_color.item_selected.connect(func(_i: int) -> void: _apply_crosshair())
	_xh_style.item_selected.connect(func(_i: int) -> void: _apply_crosshair())
	_xh_size.value_changed.connect(func(_v: float) -> void: _apply_crosshair())
	_section(body, "SHOW")
	_minimap = _check(_row(body, "Minimap"))
	_minimap.toggled.connect(func(on: bool) -> void:
		if not _filling:
			Game.set_show_minimap(on)
	)
	_killfeed = _check(_row(body, "Kill feed"))
	_killfeed.toggled.connect(func(on: bool) -> void:
		if not _filling:
			Game.set_show_killfeed(on)
	)
	_show_fps = _check(_row(body, "FPS counter"))
	_show_fps.toggled.connect(_on_show_fps)

	body = _pages[5] # Access
	_section(body, "ACCESSIBILITY")
	_colorblind = _options(_row(body, "Colourblind"), Game.COLORBLIND_NAMES)
	_colorblind.item_selected.connect(func(i: int) -> void:
		if not _filling:
			Game.set_colorblind(i)
	)
	_shake = _check(_row(body, "Less shake"))
	_shake.toggled.connect(func(on: bool) -> void:
		if not _filling:
			Game.set_reduce_shake(on)
	)
	_hint(body, "Colourblind changes the team colours on bodies, name tags, scoreboard, feed and minimap. Less shake cuts hit, blast and melee camera shake and the FOV punch to a quarter; gun recoil stays.")
	_hint(root, "Saved on this PC. Applies immediately, and again the next time you start the game.")
	show_tab(0)


func show_tab(i: int) -> void:
	_waiting_action = ""
	for j in _pages.size():
		_pages[j].visible = j == i
		_tab_buttons[j].set_pressed_no_signal(j == i)
	_refresh_bindings()
	_fit_height.call_deferred()


func _apply_crosshair() -> void:
	if _filling:
		return
	_xh_size_val.text = "%d%%" % roundi(_xh_size.value)
	Game.set_crosshair(_xh_color.selected, _xh_style.selected, _xh_size.value / 100.0)


func _start_rebind(action: String) -> void:
	_refresh_bindings()
	_waiting_action = action
	(_bind_buttons[action] as Button).text = "Press a key…"


func _refresh_bindings() -> void:
	for a in _bind_buttons:
		(_bind_buttons[a] as Button).text = Game.binding_text(a)


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not is_visible_in_tree():
		return
	var ok := false
	if event is InputEventKey and event.pressed and not event.echo:
		ok = true
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseButton and event.pressed:
		var b := (event as InputEventMouseButton).button_index
		ok = b != MOUSE_BUTTON_WHEEL_UP and b != MOUSE_BUTTON_WHEEL_DOWN
	if not ok:
		return
	get_viewport().set_input_as_handled()
	var action := _waiting_action
	_waiting_action = ""
	var swapped := Game.rebind(action, event)
	_bind_note.text = ("Swapped with %s." % swapped) if swapped != "" else "Saved."
	_refresh_bindings()


func _on_name(t: String) -> void:
	if _filling:
		return
	Game.set_player_name(t)


func _commit_name() -> void:
	if _name_edit == null:
		return
	_filling = true
	_name_edit.text = Game.player_name
	_filling = false


## Other fields (and the pause copy of this panel) changed the name. Don't eat a trailing space mid-word.
func _on_saved_name(n: String) -> void:
	if _name_edit == null or _name_edit.text == n:
		return
	if _name_edit.has_focus() and Game.clean_name(_name_edit.text) == n:
		return
	_filling = true
	_name_edit.text = n
	_filling = false


func _on_window_mode(i: int) -> void:
	if _filling:
		return
	Game.set_window_mode(i)
	_res_opt.disabled = Game.window_mode == Game.WINDOW_BORDERLESS


func _on_resolution(i: int) -> void:
	if _filling or i < 0 or i >= _res_sizes.size():
		return
	Game.set_resolution(_res_sizes[i])
	_filling = true
	_fill_resolutions()
	_filling = false


func _on_vsync(on: bool) -> void:
	if _filling:
		return
	Game.set_vsync(on)


func _on_fps(v: float) -> void:
	if _filling:
		return
	_fps_val.text = _fps_text(int(v))
	Game.set_max_fps(int(v))


func _on_fov(v: float) -> void:
	if _filling:
		return
	_fov_val.text = "%d" % roundi(v)
	Game.set_fov(v)


func _on_scale(v: float) -> void:
	if _filling:
		return
	_scale_val.text = "%d%%" % roundi(v)
	Game.set_render_scale(v / 100.0)


func _on_sway(i: int) -> void:
	if _filling:
		return
	Game.set_view_sway(i)


func _on_quality(i: int) -> void:
	if _filling:
		return
	Game.set_gfx_quality(i)


func _on_msaa(i: int) -> void:
	if _filling:
		return
	Game.set_msaa(i)


func _on_invert(on: bool) -> void:
	if _filling:
		return
	Game.set_invert_y(on)


func _on_master(v: float) -> void:
	if _filling:
		return
	Game.set_master_vol(v / 100.0)
	_refresh_audio_labels()


func _on_sfx(v: float) -> void:
	if _filling:
		return
	Game.set_sfx_vol(v / 100.0)
	_refresh_audio_labels()


func _on_show_fps(on: bool) -> void:
	if _filling:
		return
	Game.set_show_fps(on)


func _fill_resolutions() -> void:
	var choices: Array[Vector2i] = []
	for choice in Game.resolution_choices():
		choices.append(choice as Vector2i)
	if not _same_sizes(choices, _res_sizes):
		_res_sizes = choices
		_res_opt.set_block_signals(true)
		_res_opt.clear()
		for s in _res_sizes:
			_res_opt.add_item("%d×%d" % [s.x, s.y])
		_res_opt.set_block_signals(false)
	var pick := 0
	var best_d := 1 << 30
	for i in _res_sizes.size():
		var s := _res_sizes[i]
		var d := absi(s.x - Game.window_size.x) + absi(s.y - Game.window_size.y)
		if d < best_d:
			best_d = d
			pick = i
	_select_quiet(_res_opt, pick)
	_res_opt.disabled = Game.window_mode == Game.WINDOW_BORDERLESS


func _same_sizes(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _select_quiet(opt: OptionButton, index: int) -> void:
	if opt == null or opt.item_count <= 0:
		return
	opt.set_block_signals(true)
	opt.select(clampi(index, 0, opt.item_count - 1))
	opt.set_block_signals(false)


func _refresh_audio_labels() -> void:
	_master_val.text = "%d%%" % roundi(Game.master_vol * 100.0)
	_sfx_val.text = "%d%%" % roundi(Game.sfx_vol * 100.0)
	_enemies_val.text = "%d%%" % roundi(Game.enemies_vol * 100.0)
	_music_val.text = "%d%%" % roundi(Game.music_vol * 100.0)
	_ui_val.text = "%d%%" % roundi(Game.ui_vol * 100.0)


func _fps_text(v: int) -> String:
	return "Unlimited" if v <= 0 else str(v)


func _set_pair(ctl: Array, v: float) -> void:
	if ctl.size() != 2:
		return
	(ctl[0] as HSlider).set_value_no_signal(v)
	(ctl[1] as SpinBox).set_value_no_signal(v)


func _title(body: Node) -> void:
	var l := Label.new()
	l.text = "SETTINGS"
	l.theme_type_variation = &"TitleLabel"
	body.add_child(l)


func _section(body: Node, title: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	# Amber caption with a thin rule running to the right edge.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = title
	l.theme_type_variation = &"SectionLabel"
	l.add_theme_color_override("font_color", _SECTION)
	head.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(_SECTION.r, _SECTION.g, _SECTION.b, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(rule)
	body.add_child(head)


func _hint(body: Node, text: String) -> void:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(500, 0)
	hint.custom_maximum_size = Vector2(500, -1) # width cap only; -1 = no max on that axis
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hint.theme_type_variation = &"HintLabel"
	hint.add_theme_color_override("font_color", _HINT)
	body.add_child(hint)


func _row(body: Node, label_text: String) -> HBoxContainer:
	# Each setting sits on its own faint strip, like a modern shooter options list.
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"SettingRow"
	strip.custom_minimum_size = Vector2(0, 40)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(_LABEL_W, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	strip.add_child(row)
	body.add_child(strip)
	return row


func _slider(row: HBoxContainer, lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(160, 0)
	row.add_child(s)
	return s


func _value_label(row: HBoxContainer) -> Label:
	var v := Label.new()
	v.custom_minimum_size = Vector2(88, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return v


func _options(row: HBoxContainer, items: Array) -> OptionButton:
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		opt.add_item(str(item))
	row.add_child(opt)
	return opt


func _check(row: HBoxContainer) -> CheckBox:
	var box := CheckBox.new()
	row.add_child(box)
	return box


func _line_edit(row: HBoxContainer) -> LineEdit:
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


## Slider and number box move together; either one saves.
func _number_row(body: Node, label: String, lo: float, hi: float, step: float, apply: Callable) -> Array:
	var row := _row(body, label)
	var slider := _slider(row, lo, hi, step)
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = 0.01
	box.custom_minimum_size = Vector2(84, 0)
	box.select_all_on_focus = true
	row.add_child(box)
	slider.value_changed.connect(func(v: float) -> void:
		if _filling:
			return
		box.set_value_no_signal(v)
		apply.call(v)
	)
	box.value_changed.connect(func(v: float) -> void:
		if _filling:
			return
		slider.set_value_no_signal(v)
		apply.call(v)
	)
	return [slider, box]
