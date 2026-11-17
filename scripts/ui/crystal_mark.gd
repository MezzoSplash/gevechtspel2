class_name CrystalMark
extends Control
## The wordmark's crystal (docs/ui-crystal/mockups/menu.png): a pale seven-sided gem with faint
## facet lines and an ice glow on its rim, the same cut as the characters' bodies. Pure drawing,
## no input. The outline is the mockup's polygon on a 190 x 270 box, scaled to the control.

## Mockup gem outline on a 190 x 270 box (hud.html / menu.html).
const GEM := [
	Vector2(95, 4), Vector2(176, 60), Vector2(184, 160), Vector2(126, 262),
	Vector2(66, 262), Vector2(6, 160), Vector2(14, 60),
]
const BOX := Vector2(190, 270)
## Facet lines between outline points (indices into GEM), plus the spine.
const LINES := [[0, 4], [0, 3], [6, 3], [1, 4], [6, 1], [5, 2]]
const FILL := Color(0.91, 0.94, 0.97)
const SHADE := Color(0.62, 0.68, 0.76)
const LINE := Color(0.04, 0.06, 0.08, 0.28)
const GLOW := Color(0.749, 0.953, 1.0, 0.35)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(72, 102)


## The outline fitted into `area`, aspect kept, centred.
static func points(area: Vector2) -> PackedVector2Array:
	var k := minf(area.x / BOX.x, area.y / BOX.y)
	var off := (area - BOX * k) * 0.5
	var out := PackedVector2Array()
	for p in GEM:
		out.append(off + (p as Vector2) * k)
	return out


func _draw() -> void:
	var pts := points(size)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, GLOW, 6.0, true)
	draw_colored_polygon(pts, FILL)
	# One darker lower half so it reads as a cut stone, not a flat badge.
	var c := (pts[0] + pts[3] + pts[4]) / 3.0
	draw_colored_polygon(PackedVector2Array([pts[5], pts[2], pts[3], pts[4]]), Color(SHADE, 0.45))
	draw_colored_polygon(PackedVector2Array([pts[6], pts[0], c]), Color(1, 1, 1, 0.35))
	for l in LINES:
		draw_line(pts[l[0]], pts[l[1]], LINE, 1.2, true)
	draw_polyline(ring, Color(1, 1, 1, 0.55), 1.2, true)
