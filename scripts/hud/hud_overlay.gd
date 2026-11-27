class_name HudOverlay
extends Control
## Everything the HUD draws itself around the crosshair (part of the HUD): the crosshair (its gap grows
## with spread and fire punch; the sniper draws none until RMB zoom), the LOS window bar, the hurt
## vignette, the damage-direction wedges and the hit markers. The HUD adds it as its first child, so it
## draws under every other HUD node, where Hud._draw used to.

const DMG_LIFE := HudLayout.DMG_LIFE
const DMG_MAX := HudLayout.DMG_MAX
const DMG_RADIUS := HudLayout.DMG_RADIUS
const DMG_HALF := HudLayout.DMG_HALF
const HURT_TIME := 0.35 # s of red vignette after a hit
const HIT_TIME := 0.085 # s of a body hit marker; kills and headshots hold KILL_HIT_TIME
const KILL_HIT_TIME := 0.16
## #320: de lichtrand aan de muurkant tijdens een wallrun. Breedte in px bij 1080p, geschaald mee met de
## schermhoogte; de gloed volgt de resterende wallrun-tijd en trekt in de laatste 30% weg.
const WALL_EDGE_W := 190.0
const WALL_EDGE_MAX := 0.55
const WALL_EDGE_FADE := 0.30 # deel van de run waarin de rand wegtrekt

var player: Player # the local pawn: crosshair bloom and the wedges' frame of reference
var sniper_ads := false
var sniper_hip := false # sniper in hand and RMB zoom off: draw no crosshair
var hit_timer := 0.0
var kill_hit := false
var head_hit := false
var fire_punch := 0.0
var hurt_flash := 0.0
var dmg_dirs: Array[Dictionary] = [] # {pos: Vector3, t: float}: where recent damage came from
var wall_edge_side := 0 # #320: -1 muur links, +1 muur rechts, 0 geen rand (de check leest dit)
var wall_edge_amt := 0.0
## Eén gradient-textuur per kant, één keer gebouwd. Losse draw_rects gaven zichtbare strepen: de
## overlappende randen telden dubbel en 28 stappen over 190 px is te grof (review Chief op #402).
var _edge_tex := {}


func _edge_texture(bright_at_outer_left: bool) -> GradientTexture2D:
	var key := "l" if bright_at_outer_left else "r"
	if _edge_tex.has(key):
		return _edge_tex[key] as GradientTexture2D
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var n := 16
	for i in n + 1:
		var f := float(i) / float(n)
		offs.append(f)
		var k := (1.0 - f) if bright_at_outer_left else f
		cols.append(Color(1, 1, 1, pow(k, 1.7)))
	g.offsets = offs
	g.colors = cols
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 1
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.gradient = g
	_edge_tex[key] = tex
	return tex


func _init() -> void:
	name = "Overlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func tick(delta: float) -> void:
	_tick_wall_edge()
	hit_timer = maxf(hit_timer - delta, 0.0)
	fire_punch = move_toward(fire_punch, 0.0, delta * 9.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	for i in range(dmg_dirs.size() - 1, -1, -1):
		dmg_dirs[i].t = float(dmg_dirs[i].t) - delta
		if float(dmg_dirs[i].t) <= 0.0:
			dmg_dirs.remove_at(i)
	queue_redraw()


func punch(amount: float = 1.0) -> void:
	fire_punch = maxf(fire_punch, amount)
	queue_redraw()


func hit(killed: bool, headshot: bool) -> void:
	hit_timer = KILL_HIT_TIME if killed or headshot else HIT_TIME
	kill_hit = killed
	head_hit = headshot
	queue_redraw()


func hurt() -> void:
	hurt_flash = HURT_TIME
	queue_redraw()


## A red wedge around the crosshair pointing at `from_pos`. Each hit adds one (they stack, up to
## DMG_MAX); they turn with your view and fade over DMG_LIFE.
func add_damage_dir(from_pos: Vector3) -> void:
	dmg_dirs.append({"pos": from_pos, "t": DMG_LIFE})
	while dmg_dirs.size() > DMG_MAX:
		dmg_dirs.pop_front()
	queue_redraw()


func clear() -> void:
	dmg_dirs.clear()
	hurt_flash = 0.0
	queue_redraw()


## Screen angle of a world point around the crosshair: 0 = ahead (up), +PI/2 = right, PI = behind.
static func dir_angle(view: Transform3D, world_pos: Vector3) -> float:
	var to := world_pos - view.origin
	var local := view.basis.inverse() * to
	return atan2(local.x, -local.z)


func _draw() -> void:
	var c := size * 0.5
	_draw_wall_edge()
	_draw_crosshair(c)
	_draw_los_bar(c)
	_draw_hurt()
	_draw_damage_dirs(c)
	_draw_hit_marker(c)


func _draw_crosshair(c: Vector2) -> void:
	var stance := 0.0
	var p := player if is_instance_valid(player) else null
	if p:
		stance = maxf(p.spread_multiplier() - 1.0, 0.0) * 5.0
	var sz := Game.crosshair_size
	var gap := ((2.0 if sniper_ads else 5.0) + fire_punch * 7.0 + stance) * sz
	var length := 8.0 * sz
	var col := Game.crosshair_rgb()
	col.a = 0.92
	var thick := maxf(2.0 * sqrt(sz), 1.0)
	var style := Game.crosshair_style # 0 cross+dot, 1 cross, 2 dot, 3 circle
	# Hip-firing the sniper is unguided. Zoom (and every other gun) keeps the bars.
	if sniper_hip:
		return
	if style <= 1:
		_bar(c + Vector2(gap, 0), Vector2(length, 0), col, thick)
		_bar(c + Vector2(-gap, 0), Vector2(-length, 0), col, thick)
		_bar(c + Vector2(0, gap), Vector2(0, length), col, thick)
		_bar(c + Vector2(0, -gap), Vector2(0, -length), col, thick)
	elif style == 3:
		draw_arc(c, gap + length * 0.5, 0.0, TAU, 40, col, thick, true)
	if style != 1:
		draw_circle(c, (2.2 if style == 2 else 1.4) * sz, col)
	if sniper_ads:
		draw_arc(c, 22.0, 0.0, TAU, 48, Color(0.05, 0.05, 0.05, 0.45), 2.0, true)


## LOS: one thin bar under the crosshair draining with the hands' time left. Local only and drawn
## here, so it needs no node of its own. Gold, the streak family colour.
func _draw_los_bar(c: Vector2) -> void:
	var hands := LosHands.local()
	if hands == null:
		return
	var frac := clampf(hands.time_left / LosHands.DURATION, 0.0, 1.0)
	var bar_w := 96.0
	var bar_y := c.y + 34.0
	draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w, 4.0), Color(1, 1, 1, 0.16))
	draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w * frac, 4.0), Color(1, 0.92, 0.55, 0.95))


func _draw_hurt() -> void:
	if hurt_flash <= 0.0:
		return
	var red := Color(0.7, 0.05, 0.05, hurt_flash * 0.55)
	var t := 70.0
	draw_rect(Rect2(0, 0, size.x, t), red)
	draw_rect(Rect2(0, size.y - t, size.x, t), red)
	draw_rect(Rect2(0, 0, t, size.y), red)
	draw_rect(Rect2(size.x - t, 0, t, size.y), red)


func _draw_damage_dirs(c: Vector2) -> void:
	if dmg_dirs.is_empty() or not is_instance_valid(player):
		return
	var view := Transform3D(Basis(Vector3.UP, player.rotation.y), player.global_position)
	for d in dmg_dirs:
		var a := dir_angle(view, d.pos) - PI * 0.5 # draw_* angles: 0 = right, clockwise on screen
		var alpha := clampf(float(d.t) / DMG_LIFE, 0.0, 1.0)
		alpha = alpha * alpha * (3.0 - 2.0 * alpha)
		var pts := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var t := a - DMG_HALF + DMG_HALF * 2.0 * float(i) / steps
			pts.append(c + Vector2(cos(t), sin(t)) * DMG_RADIUS)
		for i in range(steps, -1, -1):
			var t := a - DMG_HALF * 0.55 + DMG_HALF * 1.1 * float(i) / steps
			pts.append(c + Vector2(cos(t), sin(t)) * (DMG_RADIUS + 26.0))
		draw_colored_polygon(pts, Color(0.92, 0.1, 0.08, 0.72 * alpha))
		var tip := c + Vector2(cos(a), sin(a)) * (DMG_RADIUS + 34.0)
		var l := c + Vector2(cos(a - 0.1), sin(a - 0.1)) * (DMG_RADIUS + 25.0)
		var r := c + Vector2(cos(a + 0.1), sin(a + 0.1)) * (DMG_RADIUS + 25.0)
		draw_colored_polygon(PackedVector2Array([l, tip, r]), Color(1.0, 0.2, 0.15, 0.85 * alpha))


## White on a body hit, gold on a headshot, red on a kill (AGENTS feel rules).
func _draw_hit_marker(c: Vector2) -> void:
	if hit_timer <= 0.0:
		return
	var hit_a := clampf(hit_timer / 0.08, 0.0, 1.0)
	var hit_col := Color(1, 1, 1, hit_a)
	if kill_hit:
		hit_col = Color(1.0, 0.22, 0.18, hit_a)
	elif head_hit:
		hit_col = Color(1.0, 0.86, 0.2, hit_a)
	var s := 11.0 if kill_hit or head_hit else 8.0
	draw_line(c + Vector2(-s, -s), c + Vector2(-s * 0.35, -s * 0.35), hit_col, 2.2, true)
	draw_line(c + Vector2(s, -s), c + Vector2(s * 0.35, -s * 0.35), hit_col, 2.2, true)
	draw_line(c + Vector2(-s, s), c + Vector2(-s * 0.35, s * 0.35), hit_col, 2.2, true)
	draw_line(c + Vector2(s, s), c + Vector2(s * 0.35, s * 0.35), hit_col, 2.2, true)


func _bar(from: Vector2, delta: Vector2, col: Color, thick: float) -> void:
	draw_line(from, from + delta, col, thick, true)


## #320: welke kant is de muur op, en hoe sterk gloeit de rand nog? Alleen de lokale speler, alleen tijdens
## een wallrun, en uit met de speed-effects-schakelaar (Access-tab). Bij dive en surf staat `_wallrunning`
## uit, dus daar komt de rand niet.
func _tick_wall_edge() -> void:
	wall_edge_side = 0
	wall_edge_amt = 0.0
	var p := player if is_instance_valid(player) else null
	if p == null or not Game.speed_fx or p.is_dead or not p.is_wallrunning():
		return
	var cam := p.camera
	if cam == null:
		return
	# De wandnormaal wijst van de muur af: zit die naar rechts, dan zit de muur links.
	var dot := p._wall_n.dot(cam.global_transform.basis.x)
	if absf(dot) < 0.05:
		return # muur recht voor of achter: geen kant om te belichten
	var remaining := 1.0 - clampf(p._wallrun_t / p.WALLRUN_TIME, 0.0, 1.0)
	if Overdrive.wallrun_free(p):
		remaining = 1.0 # een Overdrive-wallrun loopt niet af
	# Vlak voor het eind trekt de gloed weg, zodat je ziet wanneer je moet springen.
	wall_edge_amt = minf(remaining / WALL_EDGE_FADE, 1.0) * minf(p._wallrun_t / 0.08, 1.0)
	wall_edge_side = -1 if dot > 0.0 else 1


func _draw_wall_edge() -> void:
	if wall_edge_side == 0 or wall_edge_amt <= 0.01:
		return
	var w := WALL_EDGE_W * (size.y / 1080.0)
	var col := CrystalStyle.ICE
	var tint := Color(col.r, col.g, col.b, wall_edge_amt * WALL_EDGE_MAX)
	var rect := Rect2(0.0, 0.0, w, size.y) if wall_edge_side < 0 else Rect2(size.x - w, 0.0, w, size.y)
	draw_texture_rect(_edge_texture(wall_edge_side < 0), rect, false, tint)
