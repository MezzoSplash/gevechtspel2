extends VBoxContainer
## Master + SFX sliders, mouse and scope sensitivity (slider + number). Writes user://settings.cfg
## through Game. Used in the main menu and the pause menu.

var _sens: Array = [] # [HSlider, SpinBox] for mouse sensitivity
var _ads: Array = [] # same for the aim/scope multiplier


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$MasterRow/MasterSlider.value = Game.master_vol * 100.0
	$SfxRow/SfxSlider.value = Game.sfx_vol * 100.0
	_refresh_labels()
	$MasterRow/MasterSlider.value_changed.connect(_on_master)
	$SfxRow/SfxSlider.value_changed.connect(_on_sfx)
	_sens = _add_number_row(
		"SensRow", "Mouse", Game.MOUSE_SENS_MIN, Game.MOUSE_SENS_MAX, 0.05, Game.mouse_sens, Game.set_mouse_sens
	)
	_ads = _add_number_row(
		"AdsRow", "Aim / scope", Game.ADS_SENS_MIN, Game.ADS_SENS_MAX, 0.05, Game.ads_sens, Game.set_ads_sens
	)
	var hint := Label.new()
	hint.name = "SensHint"
	hint.text = "Mouse: 1.00 = default. Aim / scope multiplies it while aiming (default 0.45)."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(360, 0)
	add_child(hint)


## Slider and number box move together; either one saves.
func _add_number_row(
	row_name: String, label: String, lo: float, hi: float, step: float, value: float, apply: Callable
) -> Array:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(160, 0)
	row.add_child(slider)
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = 0.01
	box.custom_minimum_size = Vector2(84, 0)
	box.select_all_on_focus = true
	row.add_child(box)
	add_child(row)
	slider.set_value_no_signal(value)
	box.set_value_no_signal(value)
	slider.value_changed.connect(func(v: float) -> void:
		box.set_value_no_signal(v)
		apply.call(v)
	)
	box.value_changed.connect(func(v: float) -> void:
		slider.set_value_no_signal(v)
		apply.call(v)
	)
	return [slider, box]


func refresh() -> void:
	$MasterRow/MasterSlider.set_value_no_signal(Game.master_vol * 100.0)
	$SfxRow/SfxSlider.set_value_no_signal(Game.sfx_vol * 100.0)
	for pair in [[_sens, Game.mouse_sens], [_ads, Game.ads_sens]]:
		var ctl: Array = pair[0]
		if ctl.size() == 2:
			(ctl[0] as HSlider).set_value_no_signal(pair[1])
			(ctl[1] as SpinBox).set_value_no_signal(pair[1])
	_refresh_labels()


func _on_master(v: float) -> void:
	Game.set_master_vol(v / 100.0)
	_refresh_labels()


func _on_sfx(v: float) -> void:
	Game.set_sfx_vol(v / 100.0)
	_refresh_labels()


func _refresh_labels() -> void:
	$MasterRow/MasterVal.text = "%d%%" % roundi(Game.master_vol * 100.0)
	$SfxRow/SfxVal.text = "%d%%" % roundi(Game.sfx_vol * 100.0)
