class_name StreakIcon
extends Control
## #387 tegelraster: the little icon on a killstreak tile, drawn in code so it needs no model render
## and stays crisp at any size. Own shapes and own colours — the layout is borrowed, the look is ours.

const ACCENT := Color(1.0, 0.72, 0.22) # the menu's accent, same as the focus frame
const LINE := Color(0.92, 0.94, 0.98)

var streak_id: StringName = &""


func _init(id: StringName = &"") -> void:
	streak_id = id
	custom_minimum_size = Vector2(64, 64)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y) / 64.0 # everything below is drawn in a 64 px box
	match streak_id:
		&"uav":
			_draw_uav(c, s)
		&"rcxd":
			_draw_car(c, s)
		&"los":
			_draw_hands(c, s)
		&"overdrive":
			_draw_overdrive(c, s)
		_:
			draw_circle(c, 10.0 * s, LINE)


## A quadcopter seen from above: four arms, four rotors, a body.
func _draw_uav(c: Vector2, s: float) -> void:
	for a in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var rotor: Vector2 = c + a * 17.0 * s
		draw_line(c, rotor, LINE, 2.4 * s, true)
		draw_arc(rotor, 9.0 * s, 0.0, TAU, 20, ACCENT, 2.0 * s, true)
	draw_rect(Rect2(c - Vector2(8, 6) * s, Vector2(16, 12) * s), LINE, false, 2.0 * s)
	draw_circle(c, 3.0 * s, ACCENT)


## A remote-controlled car from the side: hull, cabin, two wheels.
func _draw_car(c: Vector2, s: float) -> void:
	var hull := PackedVector2Array([
		c + Vector2(-22, 6) * s, c + Vector2(22, 6) * s, c + Vector2(18, -4) * s, c + Vector2(-18, -4) * s,
	])
	draw_colored_polygon(hull, Color(LINE.r, LINE.g, LINE.b, 0.18))
	draw_polyline(hull + PackedVector2Array([hull[0]]), LINE, 2.0 * s, true)
	draw_rect(Rect2(c + Vector2(-9, -14) * s, Vector2(18, 10) * s), LINE, false, 2.0 * s)
	for w in [Vector2(-13, 9), Vector2(13, 9)]:
		draw_circle(c + w * s, 6.0 * s, ACCENT)


## The detached hands: a palm with four fingers and a thumb, a short motion line behind it.
func _draw_hands(c: Vector2, s: float) -> void:
	var palm := c + Vector2(0, 6) * s
	draw_rect(Rect2(palm - Vector2(9, 6) * s, Vector2(18, 14) * s), LINE, false, 2.0 * s)
	for i in 4:
		var x := -7.5 + float(i) * 5.0
		var top := -20.0 + absf(float(i) - 1.5) * 3.0
		draw_line(palm + Vector2(x, -6) * s, palm + Vector2(x, top) * s, LINE, 2.2 * s, true)
	draw_line(palm + Vector2(-9, 0) * s, palm + Vector2(-16, -6) * s, LINE, 2.2 * s, true)
	for i in 3:
		var y := 22.0 + float(i) * 4.0
		draw_line(c + Vector2(-14, y) * s, c + Vector2(-6, y) * s, ACCENT, 1.6 * s, true)


## Overdrive: a pawn with the crystal glow around it and a speed line behind.
func _draw_overdrive(c: Vector2, s: float) -> void:
	var glow := Color(1.0, 0.36, 0.86, 0.22)
	draw_circle(c, 24.0 * s, glow)
	draw_arc(c, 24.0 * s, 0.0, TAU, 28, Color(1.0, 0.36, 0.86), 1.8 * s, true)
	draw_circle(c + Vector2(0, -9) * s, 5.0 * s, LINE)
	draw_rect(Rect2(c + Vector2(-6, -3) * s, Vector2(12, 16) * s), LINE, false, 2.0 * s)
	for i in 2:
		var y := 4.0 + float(i) * 6.0
		draw_line(c + Vector2(-22, y) * s, c + Vector2(-14, y) * s, ACCENT, 2.0 * s, true)
