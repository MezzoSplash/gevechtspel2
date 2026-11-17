class_name CrystalStyle
extends StyleBox
## A cut-crystal shard: the UI's only shape (docs/ui-crystal/HANDOFF.md, mockups/crystal.js).
## A rectangle with four unequal chamfered corners, a fan of flat facets from one interior point,
## a faint 1 px light edge, and optionally a glowing seam along one edge. The seam carries meaning:
## team colour on score/kill feed, and on meters `seam_lit` (the lit share of the edge) is the value.
##
## The geometry helpers are static and pure so tools/check_crystal_style can test them headless.
## Every field emits `changed` when set, so a Control using this style redraws by itself.

enum Side { NONE, LEFT, BOTTOM, TOP, RIGHT }

## The two materials. Smoke glass is the default piece, pale shell is the selected/active piece.
const SMOKE := Color(0.059, 0.078, 0.106, 0.62) # #0F141B
const SHELL := Color(0.894, 0.922, 0.949, 0.96) # #E4EBF2
## Neutral seam colour ("vis"/ice). Team colours come from Player.TEAM_COLORS, never from here.
const ICE := Color(0.749, 0.953, 1.0) # #BFF3FF

const _FACET_LIGHT := Color(0.812, 0.902, 1.0) # #CFE6FF, on smoke
const _FACET_LIGHT_PALE := Color(1, 1, 1)

@export var fill := SMOKE:
	set(v): fill = v; emit_changed()
## Pale shell piece: white facets instead of ice-tinted ones.
@export var pale := false:
	set(v): pale = v; emit_changed()
@export var seam_color := ICE:
	set(v): seam_color = v; emit_changed()
@export var seam_side := Side.NONE:
	set(v): seam_side = v; emit_changed()
## Lit share of the seam edge, 0..1. The rest of the edge shows a faint track.
@export_range(0.0, 1.0) var seam_lit := 1.0:
	set(v): seam_lit = clampf(v, 0.0, 1.0); emit_changed()
## Chamfer size in px per corner: x = top-left, y = top-right, z = bottom-right, w = bottom-left.
@export var cuts := Vector4(14, 6, 18, 8):
	set(v): cuts = v; emit_changed()
## 0 = flat fill, 1 = the mockup's facet contrast.
@export_range(0.0, 2.0) var facet_strength := 1.0:
	set(v): facet_strength = v; emit_changed()
## Seed for the facet fan. Same variant, same facets.
@export var variant := 1:
	set(v): variant = v; emit_changed()
@export_range(0.0, 1.0) var edge_alpha := 0.16:
	set(v): edge_alpha = v; emit_changed()


## The 8-point outline, clockwise from the top-left cut: (tl,0) (w-tr,0) (w,tr) (w,h-br)
## (w-br,h) (bl,h) (0,h-bl) (0,tl). Each cut is clamped to min(w,h)*0.45 so opposite cuts never
## meet, and kept at least 1 px (or the clamp, on a tiny rect) so no two points coincide.
static func outline(rect: Rect2, c: Vector4) -> PackedVector2Array:
	var w := rect.size.x
	var h := rect.size.y
	var lim := minf(w, h) * 0.45
	var lo := minf(1.0, lim)
	var tl := clampf(c.x, lo, lim)
	var tr := clampf(c.y, lo, lim)
	var br := clampf(c.z, lo, lim)
	var bl := clampf(c.w, lo, lim)
	var o := rect.position
	return PackedVector2Array([
		o + Vector2(tl, 0), o + Vector2(w - tr, 0),
		o + Vector2(w, tr), o + Vector2(w, h - br),
		o + Vector2(w - br, h), o + Vector2(bl, h),
		o + Vector2(0, h - bl), o + Vector2(0, tl),
	])


## The facet fan: one triangle per outline edge to a seeded interior point (middle half of the
## rect). Returns [{tri: PackedVector2Array, light: bool, alpha: float}], same list for the same
## variant. Alpha is the mockup's opacity before facet_strength.
static func facets(pts: PackedVector2Array, rect: Rect2, seed_variant: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_variant * 977 + 13)
	var centre := rect.position + rect.size * Vector2(0.25 + 0.5 * rng.randf(), 0.25 + 0.5 * rng.randf())
	var out: Array = []
	for i in pts.size():
		var light := rng.randf() < 0.55
		var alpha := 0.04 + 0.11 * rng.randf() if light else 0.05 + 0.2 * rng.randf()
		out.append({"tri": PackedVector2Array([pts[i], pts[(i + 1) % pts.size()], centre]), "light": light, "alpha": alpha})
	return out


## Start and end of the seam on `side`, moved `inset` px into the shard so the glow is not cut off
## by the edge. LEFT runs top to bottom, BOTTOM and TOP left to right, RIGHT top to bottom, so a
## partly lit meter fills from the start. Empty for Side.NONE.
static func seam_ends(pts: PackedVector2Array, side: int, inset := 2.0) -> Array[Vector2]:
	match side:
		Side.LEFT:
			return [pts[7] + Vector2(inset, 0), pts[6] + Vector2(inset, 0)]
		Side.BOTTOM:
			return [pts[5] - Vector2(0, inset), pts[4] - Vector2(0, inset)]
		Side.TOP:
			return [pts[0] + Vector2(0, inset), pts[1] + Vector2(0, inset)]
		Side.RIGHT:
			return [pts[2] - Vector2(inset, 0), pts[3] - Vector2(inset, 0)]
	return []


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return
	var rs := RenderingServer
	var pts := outline(rect, cuts)
	if fill.a > 0.0:
		rs.canvas_item_add_polygon(to_canvas_item, pts, _same(fill, pts.size()))
		if facet_strength > 0.0:
			var lit_tint := _FACET_LIGHT_PALE if pale else _FACET_LIGHT
			for f in facets(pts, rect, variant):
				var col: Color = lit_tint if f.light else Color.BLACK
				col.a = minf(1.0, f.alpha * facet_strength) * fill.a
				rs.canvas_item_add_polygon(to_canvas_item, f.tri, _same(col, 3))
	if edge_alpha > 0.0:
		var ring := pts.duplicate()
		ring.append(pts[0])
		rs.canvas_item_add_polyline(to_canvas_item, ring, _same(Color(1, 1, 1, edge_alpha), ring.size()), 1.0, true)
	if seam_side != Side.NONE:
		var e := seam_ends(pts, seam_side)
		var track := seam_color
		track.a *= 0.25
		rs.canvas_item_add_line(to_canvas_item, e[0], e[1], track, 2.0, true)
		if seam_lit > 0.0:
			var tip: Vector2 = e[0].lerp(e[1], seam_lit)
			var glow := seam_color
			glow.a *= 0.22
			rs.canvas_item_add_line(to_canvas_item, e[0], tip, glow, 9.0, true)
			rs.canvas_item_add_line(to_canvas_item, e[0], tip, seam_color, 3.0, true)


static func _same(c: Color, n: int) -> PackedColorArray:
	var a := PackedColorArray()
	a.resize(n)
	a.fill(c)
	return a
