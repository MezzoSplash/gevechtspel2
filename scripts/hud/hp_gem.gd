class_name HpGem
extends Control
## #319: de HP-gem, het laatste open stuk van de crystal-HUD. Een kristalschil links in de HP-rij met twee
## gloeiende seams: de onderste is HP (ijzig, de verlichte lengte is de HP), de tweede erboven is de
## armour van de Schildplaat (lichter blauw). Bij een hit springen er facetten af die doven, en bij regen
## groeit de seam rustig terug. Onder `LOW_FRAC` pulseert de HP-seam rood, zodat je het in een ooghoek
## ziet, ook midden in een surf.
##
## Tekent met dezelfde regels als de rest van de HUD (CrystalStyle: cuts, facets, seam), en houdt zijn
## eigen stand bij zodat tools/check_hp_gem het zonder match kan nameten.

const CUTS := Vector4(7.0, 3.0, 5.0, 2.0)
const LOW_FRAC := 0.3
const CHIP_TIME := 0.5
const CHIP_ALPHA := 0.5
const ARMOUR_COL := Color(0.62, 0.86, 1.0) # ijziger dan de HP-seam
const DANGER := Color(0.92, 0.2, 0.16) # alleen gevaar, zoals het brief voorschrijft
const SEAM_W := 3.0
const ARMOUR_W := 2.5

var hp_frac := 1.0
var armour_frac := 0.0
var shown := 1.0 # wat er getekend wordt: groeit terug naar hp_frac na regen
var chips: Array[Dictionary] = [] # {from: Vector2, dir: Vector2, t: float}
var _pulse := 0.0
var _chips_spawned := 0


func _init() -> void:
	name = "HpGem"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Hoogte gelijk aan de HP-rij zelf (28) plus marge: een hogere gem duwt de hele stapel omhoog en dan
## raakt de combo-meter de crosshair (check_hud_layout).
	custom_minimum_size = Vector2(56, 30)


## HP, max HP, armour en max armour. Een daling laat facetten afspringen; regen laat de seam teruggroeien.
func set_state(hp: float, max_hp: float, armour := 0.0, max_armour := 100.0) -> void:
	var before := hp_frac
	hp_frac = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	armour_frac = clampf(armour / maxf(max_armour, 1.0), 0.0, 1.0)
	if hp_frac < before - 0.001:
		_spawn_chips(maxi(2, int((before - hp_frac) * 10.0)))
		if hp_frac > shown:
			shown = hp_frac # harder dan wat er nog stond: meteen korter
	queue_redraw()


## De seam groeit rustig terug naar de echte HP, de facetten doven uit.
func tick(delta: float) -> void:
	_pulse += delta
	if shown < hp_frac:
		shown = minf(shown + delta * 0.6, hp_frac) # herstel: facetten groeien terug
	elif shown > hp_frac:
		shown = maxf(shown - delta * 3.0, hp_frac)
	for i in range(chips.size() - 1, -1, -1):
		chips[i].t = float(chips[i].t) + delta
		if float(chips[i].t) >= CHIP_TIME:
			chips.remove_at(i)
	queue_redraw()


## De verlichte lengte van de HP-seam (0..1), voor de check.
func seam_lit() -> float:
	return clampf(shown, 0.0, 1.0)


func armour_lit() -> float:
	return armour_frac


func is_low() -> bool:
	return hp_frac <= LOW_FRAC


func _spawn_chips(n: int) -> void:
	var rect := Rect2(Vector2(2, 4), Vector2(size.x - 4, size.y - 8))
	for i in n:
		_chips_spawned += 1
		# Deterministisch verdeeld (geen rng): een vaste fan van richtingen, zodat de check en een
		# replay hetzelfde zien.
		var f := float(_chips_spawned % 7) / 6.0
		var from := rect.position + Vector2(rect.size.x * (0.15 + 0.7 * f), rect.size.y * 0.5)
		var dir := Vector2(0.4 - 0.8 * f, -0.6 - 0.4 * f).normalized()
		chips.append({"from": from, "dir": dir, "t": 0.0})


func _draw() -> void:
	var rect := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var pts := CrystalStyle.outline(rect, CUTS)
	draw_colored_polygon(pts, CrystalStyle.SMOKE)
	for f in CrystalStyle.facets(pts, rect, 319):
		var tri: PackedVector2Array = f["tri"]
		var lit := bool(f["light"])
		var a := float(f["alpha"]) * 2.2
		var col := Color(0.81, 0.90, 1.0, a) if lit else Color(0.02, 0.03, 0.05, a)
		draw_colored_polygon(tri, col)
	draw_polyline(pts, Color(0.81, 0.90, 1.0, 0.22), 1.0, true)

	# De twee seams aan de onderkant: HP onder, armour erboven.
	var ends := CrystalStyle.seam_ends(pts, CrystalStyle.Side.BOTTOM, 3.0)
	if ends.size() == 2:
		_draw_seam(ends[0], ends[1], seam_lit(), _hp_color(), SEAM_W)
		_draw_seam(ends[0] - Vector2(0, ARMOUR_W + 3.5), ends[1] - Vector2(0, ARMOUR_W + 3.5),
			armour_lit(), ARMOUR_COL, ARMOUR_W)

	# De facetten die afsprongen bij de laatste hit: ze doven en vallen weg.
	for c in chips:
		var t := float(c.t) / CHIP_TIME
		var at: Vector2 = (c.from as Vector2) + (c.dir as Vector2) * (6.0 + 16.0 * t)
		var s := 3.0 * (1.0 - t * 0.6)
		var col := Color(0.81, 0.90, 1.0, CHIP_ALPHA * (1.0 - t))
		draw_colored_polygon(PackedVector2Array([at + Vector2(-s, -s * 0.4), at + Vector2(s, 0.0), at + Vector2(0.0, s)]), col)


func _draw_seam(from: Vector2, to: Vector2, lit: float, col: Color, width: float) -> void:
	# De onverlichte rest blijft als doffe lijn staan, zodat je de volle maat blijft zien.
	draw_line(from, to, Color(0.75, 0.90, 1.0, 0.14), width, true)
	if lit <= 0.001:
		return
	var end := from.lerp(to, clampf(lit, 0.0, 1.0))
	draw_line(from, end, Color(col.r, col.g, col.b, col.a * 0.35), width + 4.0, true)
	draw_line(from, end, col, width, true)


func _hp_color() -> Color:
	if not is_low():
		return CrystalStyle.ICE
	# Bijna dood: de seam pulseert rood. Rustig, geen knipperen.
	var k := 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse * 7.0))
	return CrystalStyle.ICE.lerp(DANGER, k)
