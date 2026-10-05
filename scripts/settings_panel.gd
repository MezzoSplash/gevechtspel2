extends ScrollContainer
## Name, video, mouse, audio and the FPS counter. Writes user://settings.cfg through Game.
## Used in the main menu and the pause menu. Built in code so both stay the same screen.

const _LABEL_W := 130.0
const _SECTION := Color(0.93, 0.78, 0.42)
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
var _sens: Array = [] # [HSlider, SpinBox]
var _ads: Array = []
var _invert: CheckBox
var _master: HSlider
var _master_val: Label
var _sfx: HSlider
var _sfx_val: Label
var _show_fps: CheckBox
var _filling := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	custom_minimum_size.x = 520
	($Body as Control).custom_minimum_size.x = 500
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


## Tall enough to scroll on a 720p window, short enough that Back stays on screen.
func _fit_height() -> void:
	if not is_inside_tree():
		return
	var want := ($Body as Control).get_combined_minimum_size().y
	# Hidden on the first frame the minimum can still be 0. A floor keeps the list from collapsing.
	if want < 40.0:
		want = 480.0
	var avail := get_viewport().get_visible_rect().size.y - 150.0
	custom_minimum_size.y = minf(want, maxf(avail, 280.0))


func refresh() -> void:
	if _name_edit == null:
		return
	_filling = true
	if not _name_edit.has_focus():
		_name_edit.text = Game.player_name
	_window_opt.select(clampi(Game.window_mode, 0, 2))
	_fill_resolutions()
	_vsync.set_pressed_no_signal(Game.vsync)
	_fps.set_value_no_signal(Game.max_fps)
	_fps_val.text = _fps_text(Game.max_fps)
	_fov.set_value_no_signal(Game.fov)
	_fov_val.text = "%d" % roundi(Game.fov)
	_scale.set_value_no_signal(Game.render_scale * 100.0)
	_scale_val.text = "%d%%" % roundi(Game.render_scale * 100.0)
	_msaa.select(clampi(Game.msaa, 0, 3))
	_set_pair(_sens, Game.mouse_sens)
	_set_pair(_ads, Game.ads_sens)
	_invert.set_pressed_no_signal(Game.invert_y)
	_master.set_value_no_signal(Game.master_vol * 100.0)
	_sfx.set_value_no_signal(Game.sfx_vol * 100.0)
	_show_fps.set_pressed_no_signal(Game.show_fps)
	_refresh_audio_labels()
	_filling = false
	_fit_height()


func _build() -> void:
	var body := $Body
	_title(body)
	_section(body, "NAME")
	_name_edit = _line_edit(_row(body, "Name"))
	_name_edit.placeholder_text = "Player"
	_name_edit.max_length = Game.NAME_MAX
	_name_edit.text_changed.connect(_on_name)
	_name_edit.focus_exited.connect(_commit_name)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_section(body, "VIDEO")
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
	var scale_row := _row(body, "Render scale")
	_scale = _slider(scale_row, 50, 100, 5)
	_scale_val = _value_label(scale_row)
	_scale.value_changed.connect(_on_scale)
	_msaa = _options(_row(body, "Antialiasing"), ["Off", "2×", "4×", "8×"])
	_msaa.item_selected.connect(_on_msaa)
	_hint(body, "VSync follows the monitor. Max FPS is an extra cap; Unlimited means no cap. Borderless uses the monitor's resolution. Render scale changes the 3D image only.")
	_section(body, "MOUSE")
	_sens = _number_row(body, "Mouse", Game.MOUSE_SENS_MIN, Game.MOUSE_SENS_MAX, 0.05, Game.set_mouse_sens)
	_ads = _number_row(body, "Aim / scope", Game.ADS_SENS_MIN, Game.ADS_SENS_MAX, 0.05, Game.set_ads_sens)
	_invert = _check(_row(body, "Invert Y"))
	_invert.toggled.connect(_on_invert)
	_hint(body, "Mouse: 1.00 = default. Aim / scope multiplies it while aiming (default 0.45).")
	_section(body, "AUDIO")
	var master_row := _row(body, "Master")
	_master = _slider(master_row, 0, 100, 1)
	_master_val = _value_label(master_row)
	_master.value_changed.connect(_on_master)
	var sfx_row := _row(body, "SFX")
	_sfx = _slider(sfx_row, 0, 100, 1)
	_sfx_val = _value_label(sfx_row)
	_sfx.value_changed.connect(_on_sfx)
	_section(body, "HUD")
	_show_fps = _check(_row(body, "FPS counter"))
	_show_fps.toggled.connect(_on_show_fps)
	_hint(body, "Saved on this PC. Applies immediately, and again the next time you start the game.")


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
	_res_sizes.clear()
	for choice in Game.resolution_choices():
		_res_sizes.append(choice as Vector2i)
	_res_opt.clear()
	var pick := 0
	var best_d := 1 << 30
	for i in _res_sizes.size():
		var s := _res_sizes[i]
		_res_opt.add_item("%d×%d" % [s.x, s.y])
		var d := absi(s.x - Game.window_size.x) + absi(s.y - Game.window_size.y)
		if d < best_d:
			best_d = d
			pick = i
	if _res_opt.item_count > 0:
		_res_opt.select(pick)
	_res_opt.disabled = Game.window_mode == Game.WINDOW_BORDERLESS


func _refresh_audio_labels() -> void:
	_master_val.text = "%d%%" % roundi(Game.master_vol * 100.0)
	_sfx_val.text = "%d%%" % roundi(Game.sfx_vol * 100.0)


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
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	body.add_child(l)


func _section(body: Node, title: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", _SECTION)
	body.add_child(l)


func _hint(body: Node, text: String) -> void:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(500, 0)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", _HINT)
	body.add_child(hint)


func _row(body: Node, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(_LABEL_W, 0)
	row.add_child(l)
	body.add_child(row)
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
