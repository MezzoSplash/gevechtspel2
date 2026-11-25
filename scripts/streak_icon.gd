class_name StreakIcon
extends Control
## #387 tegelraster: the icon on a killstreak tile, drawn in code so it needs no model render and stays
## crisp at any size. One drawing box, one line weight and one accent for all four, so the tiles read
## as a set — the look is ours, not borrowed art.

const ACCENT := Color(1.0, 0.72, 0.22)
const LINE := Color(0.94, 0.95, 0.98)
const STROKE := 1.8 # base line width in the 64 px box, scaled with the control
const S := 21.0 # half the drawing box: every shape stays inside this

var streak_id: StringName = &""


func _init(id: StringName = &"") -> void:
	streak_id = id
	custom_minimum_size = Vector2(64, 64)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var k := minf(size.x, size.y) / 64.0 # everything below is drawn in a 64 px box
	match streak_id:
		&"uav":
			_draw_uav(c, k)
		&"rcxd":
			_draw_car(c, k)
		&"los":
			_draw_hand(c, k)
		&"overdrive":
			_draw_run(c, k)
		_:
			draw_circle(c, S * 0.2 * k, LINE)


## Quadcopter from above: four arms to four rotors, a body in the middle.
func _draw_uav(c: Vector2, k: float) -> void:
	for a in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var rotor: Vector2 = c + a * (S * 0.72) * k
		draw_line(c, rotor, LINE, STROKE * k, true)
		draw_arc(rotor, S * 0.3 * k, 0.0, TAU, 22, LINE, STROKE * k, true)
	draw_rect(Rect2(c - Vector2(S * 0.3, S * 0.24) * k, Vector2(S * 0.6, S * 0.48) * k), LINE, false, STROKE * k)
	draw_circle(c, S * 0.14 * k, ACCENT)


## RC car from the side: hull, cabin, two wheels.
func _draw_car(c: Vector2, k: float) -> void:
	var hull := PackedVector2Array([
		c + Vector2(-S, S * 0.34) * k, c + Vector2(S, S * 0.34) * k,
		c + Vector2(S * 0.82, -S * 0.2) * k, c + Vector2(-S * 0.82, -S * 0.2) * k,
	])
	draw_colored_polygon(hull, Color(LINE.r, LINE.g, LINE.b, 0.16))
	draw_polyline(hull + PackedVector2Array([hull[0]]), LINE, STROKE * k, true)
	draw_rect(Rect2(c + Vector2(-S * 0.42, -S * 0.68) * k, Vector2(S * 0.84, S * 0.48) * k), LINE, false, STROKE * k)
	for w in [Vector2(-S * 0.6, S * 0.5), Vector2(S * 0.6, S * 0.5)]:
		draw_circle(c + w * k, S * 0.28 * k, ACCENT)


## The hand that leaves the body: a palm, four fingers, a thumb — and nothing else. The earlier cluster
## of strokes under it read as a stray "≡" on the tile (#387 review).
func _draw_hand(c: Vector2, k: float) -> void:
	var palm := c + Vector2(0, S * 0.34) * k
	draw_rect(Rect2(palm - Vector2(S * 0.42, S * 0.3) * k, Vector2(S * 0.84, S * 0.7) * k), LINE, false, STROKE * k)
	for i in 4:
		var x := -S * 0.36 + float(i) * (S * 0.24)
		var top := -S * 0.92 + absf(float(i) - 1.5) * S * 0.14
		draw_line(palm + Vector2(x, -S * 0.3) * k, palm + Vector2(x, top) * k, LINE, STROKE * k, true)
	draw_line(palm + Vector2(-S * 0.42, 0) * k, palm + Vector2(-S * 0.8, -S * 0.28) * k, LINE, STROKE * k, true)


## Overdrive: a body in full stride with speed lines behind it. A glowing dot said nothing about what
## the streak does; this reads as "fast" at tile size (#387 review).
func _draw_run(c: Vector2, k: float) -> void:
	var hip := c + Vector2(S * 0.08, S * 0.14) * k
	var head := c + Vector2(S * 0.26, -S * 0.64) * k
	var shoulder := c + Vector2(S * 0.12, -S * 0.26) * k
	draw_circle(head, S * 0.19 * k, LINE)
	draw_line(shoulder, hip, LINE, STROKE * k, true)
	draw_line(hip, c + Vector2(-S * 0.34, S * 0.86) * k, LINE, STROKE * k, true)
	draw_line(hip, c + Vector2(S * 0.6, S * 0.72) * k, LINE, STROKE * k, true)
	draw_line(shoulder, c + Vector2(-S * 0.38, S * 0.04) * k, LINE * Color(1, 1, 1, 0.95), STROKE * k, true)
	draw_line(shoulder, c + Vector2(S * 0.64, -S * 0.12) * k, LINE, STROKE * k, true)
	for i in 3:
		var y := -S * 0.5 + float(i) * S * 0.45
		draw_line(c + Vector2(-S * 0.98, y) * k, c + Vector2(-S * 0.5, y) * k, ACCENT, STROKE * k, true)
