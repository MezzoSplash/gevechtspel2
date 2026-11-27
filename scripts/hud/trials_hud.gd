extends CanvasLayer
## HUD voor Trials (#325): klok, checkpoint-voortgang, beste tijd en de besturing. Bouwt zichzelf, zodat
## de gewone HUD (levens, munitie, scores) er niets van hoeft te weten.

const MARGIN := 28.0

var _line_label: Label
var _clock: Label
var _progress: Label
var _best: Label
var _hint: Label
var _result: Label


func _ready() -> void:
	layer = 8
	var box := VBoxContainer.new()
	box.name = "TrialsPanel"
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_left = MARGIN
	box.offset_right = -MARGIN
	box.offset_top = MARGIN
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_line_label = _label("", 22)
	_clock = _label("0.00s", 64)
	_progress = _label("", 20)
	_best = _label("", 18)
	box.add_child(_line_label)
	box.add_child(_clock)
	box.add_child(_progress)
	box.add_child(_best)
	_result = _label("", 28)
	_result.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result.offset_top = 220.0
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_result)
	_hint = _label("R opnieuw  ·  T volgende lijn  ·  Esc menu", 16)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -46.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


func _label(text: String, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func bind(run: Node) -> void:
	if run == null:
		return
	if run.has_signal("finished") and not run.finished.is_connected(_on_finished):
		run.finished.connect(_on_finished)
	if run.has_signal("line_switched") and not run.line_switched.is_connected(_on_line_switched):
		run.line_switched.connect(_on_line_switched)


func _on_finished(ms: int, is_best: bool) -> void:
	_result.text = ("NIEUW RECORD  " if is_best else "Klaar  ") + Trials.format_ms(ms)
	_result.add_theme_color_override("font_color", Color(1.0, 0.87, 0.4) if is_best else Color(0.9, 0.97, 1.0))


func _on_line_switched(_i: int) -> void:
	_result.text = ""


## Elke frame vanuit main: de runner is de bron van de where.
func refresh(run: Node) -> void:
	if run == null:
		return
	var line: Dictionary = run.current_line()
	_line_label.text = "TRIALS  %s" % String(line.get("name", ""))
	_clock.text = Trials.format_ms(int(run.run_ms))
	var best: int = int(run.best)
	_best.text = ("Beste %s" % Trials.format_ms(best)) if best > 0 else "Nog geen tijd"
	var d: String = run.delta_vs_best()
	_progress.text = "Checkpoint %s%s%s" % [run.progress_text(), "   " if d != "" else "", d]
	if not run.finished_run:
		return
	_clock.text = Trials.format_ms(int(run.run_ms))
