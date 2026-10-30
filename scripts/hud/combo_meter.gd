class_name ComboMeter
extends VBoxContainer
## #84 combo meter (part of the HUD): total × multiplier, the moves, a draining bar (red near the end),
## LANDED / BAILED, and the combo sounds. The HUD feeds it Game.combo_changed and ticks it.

## Combo SFX (original, tools/gen_combo_sfx.py). Local player only: the server sends combo state to its owner.
const _DING := preload("res://assets/sounds/combo_ding.wav")
const _SPECIAL := preload("res://assets/sounds/combo_special.wav")
const _LAND := preload("res://assets/sounds/combo_land.wav")
const _BAIL := preload("res://assets/sounds/combo_bail.wav")
const SPECIAL_MOVES := ["WALLRUN", "WALL JUMP", "WALL TO WALL", "DIVE", "ROLL"]
const SFX_GAP := 0.09 # s: moves closer than this share one sound (no machine-gun dings)
const PITCH_STEP := 0.06 # per MULT_STEP of multiplier
const PITCH_MAX := 1.8


const COLOR := Color(1.0, 0.82, 0.3)
const WARN_COLOR := Color(0.95, 0.3, 0.25)
const FROZEN_COLOR := Color(0.45, 0.85, 1.0) # #89: surf holds the combo timer
const LANDED_COLOR := Color(0.45, 0.95, 0.5)
var total: Label
var moves_label: Label
var bar: ProgressBar
var fill: StyleBoxFlat
var _left := 0.0
var sfx: AudioStreamPlayer
var _sfx_t := -10.0 # last combo sound (s, ticks)
var _last_pts := 0
var sfx_log: Array = [] # [kind, pitch] for the headless check
var frozen := false
var _tw: Tween


func _init() -> void:
	name = "Combo"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.66
	anchor_bottom = 0.66
	offset_left = -220.0
	offset_right = 220.0
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)
	total = Label.new()
	total.name = "Total"
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total.add_theme_font_size_override("font_size", 40)
	total.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	total.add_theme_constant_override("outline_size", 8)
	add_child(total)
	moves_label = Label.new()
	moves_label.name = "Moves"
	moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_label.add_theme_font_size_override("font_size", 15)
	moves_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	moves_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	moves_label.add_theme_constant_override("outline_size", 4)
	add_child(moves_label)
	bar = ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, 7)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.max_value = Combo.TIME
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	fill = StyleBoxFlat.new()
	fill.bg_color = COLOR
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	visible = false


func on_combo_changed(points: int, multiplier: float, time_left: float, moves: String, state: String, banked: int) -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	visible = true
	modulate.a = 1.0
	_sound(points, multiplier, moves, state)
	var mult := String.num(multiplier, 1).trim_suffix(".0")
	if state == "frozen":
		# #89: surfing holds the timer; the bar stays put until the server sends "build" again.
		frozen = true
		_left = time_left
		bar.value = time_left
		bar.visible = true
		total.text = "%d  ×%s" % [points, mult]
		total.add_theme_color_override("font_color", FROZEN_COLOR)
		fill.bg_color = FROZEN_COLOR
		moves_label.text = "%s  ·  SURF: TIMER HELD" % moves if moves != "" else "SURF: TIMER HELD"
		return
	frozen = false
	if state == "build":
		_left = time_left
		total.text = "%d  ×%s" % [points, mult]
		total.add_theme_color_override("font_color", COLOR)
		moves_label.text = moves
		bar.visible = true
		pivot_offset = size * 0.5
		scale = Vector2(1.12, 1.12)
		_tw = create_tween()
		_tw.tween_property(self, "scale", Vector2.ONE, 0.12)
		return
	_left = 0.0
	bar.visible = false
	if state == "landed":
		total.text = "LANDED  +%d" % banked
		total.add_theme_color_override("font_color", LANDED_COLOR)
		moves_label.text = "%d × %s" % [points, mult]
	else:
		total.text = "BAILED"
		total.add_theme_color_override("font_color", WARN_COLOR)
		moves_label.text = "%d × %s lost" % [points, mult]
	_tw = create_tween()
	_tw.tween_interval(1.2)
	_tw.tween_property(self, "modulate:a", 0.0, 0.5)
	_tw.tween_callback(func() -> void: visible = false)


func _sound(points: int, multiplier: float, moves: String, state: String) -> void:
	var prev := _last_pts
	_last_pts = points if state == "build" or state == "frozen" else 0
	var kind := ""
	var pitch := 1.0
	if state == "landed":
		kind = "land"
	elif state == "bailed":
		kind = "bail"
	elif points > prev:
		var last := moves.get_slice(" > ", moves.get_slice_count(" > ") - 1)
		kind = "special" if last in SPECIAL_MOVES else "ding"
		pitch = minf(1.0 + PITCH_STEP * (multiplier - Combo.MULT_START) / Combo.MULT_STEP, PITCH_MAX)
	if kind == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if (kind == "ding" or kind == "special") and now - _sfx_t < SFX_GAP:
		return
	_sfx_t = now
	if sfx == null:
		sfx = AudioStreamPlayer.new()
		sfx.bus = "UI"
		sfx.max_polyphony = 3
		add_child(sfx)
	var streams := {"ding": _DING, "special": _SPECIAL, "land": _LAND, "bail": _BAIL}
	sfx.stream = streams[kind]
	sfx.pitch_scale = pitch
	sfx.volume_db = -6.0 if kind == "ding" else -3.0
	sfx.play()
	sfx_log.append([kind, pitch])


## The server ends it (timeout / death / kill); the bar only shows the time it already said is left.
func tick(delta: float) -> void:
	if not bar.visible or _left <= 0.0 or frozen:
		return
	_left = maxf(_left - delta, 0.0)
	bar.value = _left
	var warn := _left <= Combo.WARN
	fill.bg_color = WARN_COLOR if warn else COLOR
	total.add_theme_color_override("font_color", WARN_COLOR if warn else COLOR)


func reset() -> void:
	_left = 0.0
	visible = false
