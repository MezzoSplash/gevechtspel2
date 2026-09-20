extends VBoxContainer
## Master + SFX sliders. Writes user://settings.cfg through Game.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$MasterRow/MasterSlider.value = Game.master_vol * 100.0
	$SfxRow/SfxSlider.value = Game.sfx_vol * 100.0
	_refresh_labels()
	$MasterRow/MasterSlider.value_changed.connect(_on_master)
	$SfxRow/SfxSlider.value_changed.connect(_on_sfx)


func refresh() -> void:
	$MasterRow/MasterSlider.set_value_no_signal(Game.master_vol * 100.0)
	$SfxRow/SfxSlider.set_value_no_signal(Game.sfx_vol * 100.0)
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
