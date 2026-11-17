class_name SpeedMeter
extends Control
## Speed readout at the bottom centre of the HUD: horizontal speed in m/s, a bar that fills towards MAX_SPEED
## and what the pawn is doing (WALLRUN, SURF, SLIDE, DIVE). Local pawn only; the HUD feeds it every frame.
## Pure drawing and two statics, so tools/check_speed_meter.gd can cover the maths without a match.

const MAX_SPEED := 40.0 # m/s at which the bar is full (surf exits go well past sprint, which is 11.4)
const SPRINT_MARK := 11.4 # m/s, Player.SPRINT_SPEED: the tick on the bar for "normal top speed"
const COLD := Color(0.13, 0.83, 1.0)
const HOT := Color(0.85, 1.0, 0.17)
const BAR_W := 520.0
const BAR_H := 12.0

var speed := 0.0
var state := ""
var _num: Label
var _state: Label
var _unit: Label


## Horizontal speed in m/s.
static func flat_speed(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## 0..1 fill of the bar for a speed.
static func fill_of(s: float) -> float:
	return clampf(s / MAX_SPEED, 0.0, 1.0)


## What the pawn is doing, in the priority a player would name it. "" while just running or standing.
static func state_of(p: Player) -> String:
	if p == null:
		return ""
	if p._wallrunning:
		return "WALLRUN"
	if p._diving:
		return "DIVE"
	if p._sliding:
		return "SLIDE"
	if p.is_surfing():
		return "SURF"
	return ""


func _init() -> void:
	name = "Speed"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -BAR_W * 0.5
	offset_right = BAR_W * 0.5
	offset_top = -150.0
	offset_bottom = -20.0
	_num = Label.new()
	_num.name = "Num"
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num.position = Vector2(0, 0)
	_num.size = Vector2(BAR_W - 70.0, 80.0)
	_num.add_theme_font_size_override("font_size", 64)
	_num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_num.add_theme_constant_override("outline_size", 8)
	add_child(_num)
	_unit = Label.new()
	_unit.name = "Unit"
	_unit.text = "M/S"
	_unit.position = Vector2(BAR_W - 66.0, 40.0)
	_unit.add_theme_font_size_override("font_size", 18)
	_unit.add_theme_color_override("font_color", COLD)
	_unit.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_unit.add_theme_constant_override("outline_size", 4)
	add_child(_unit)
	_state = Label.new()
	_state.name = "State"
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state.position = Vector2(0, 104.0)
	_state.size = Vector2(BAR_W, 24.0)
	_state.add_theme_font_size_override("font_size", 16)
	_state.add_theme_color_override("font_color", HOT)
	_state.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_state.add_theme_constant_override("outline_size", 4)
	add_child(_state)
	set_process(false)


func update_from(v: Vector3, st: String) -> void:
	speed = flat_speed(v)
	state = st
	_num.text = str(roundi(speed))
	_state.text = st
	_num.add_theme_color_override("font_color", COLD.lerp(HOT, fill_of(speed)).lerp(Color.WHITE, 0.35))
	queue_redraw()


func _draw() -> void:
	var y := 84.0
	draw_rect(Rect2(0, y, BAR_W, BAR_H), Color(0.04, 0.05, 0.07, 0.8))
	var f := fill_of(speed)
	if f > 0.0:
		var w := BAR_W * f
		draw_rect(Rect2(0, y, w, BAR_H), COLD.lerp(HOT, f))
	var mark := BAR_W * fill_of(SPRINT_MARK)
	draw_rect(Rect2(mark - 1.0, y - 3.0, 2.0, BAR_H + 6.0), Color(1, 1, 1, 0.7))
