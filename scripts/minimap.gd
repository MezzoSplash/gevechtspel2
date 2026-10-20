class_name Minimap
extends Control
## BO2 style minimap, top left. Rotates with the local pawn (up = where you look).
## Always: map outline (CSG boxes of the loaded map), you (arrow) and living teammates.
## Enemies: all of them while your side has a UAV running (Game.radar_left), and for a moment
## at the spot where they fire (no suppressors in the game, so every shot shows).
## Purely local drawing: positions come from the already synced pawns, no extra RPCs.

const RANGE := 34.0 # metres from centre to the edge
const SHOT_SHOW_MS := 1400 # an enemy shot stays as a red dot this long
const FADE_MS := 1000 # lost contact: the dot stays at its last known spot and fades this long
const UAV_SWEEP := 2.0 # seconds per UAV sweep line turn

var _map_ref: WeakRef = weakref(null)
var _floors: Array[PackedVector2Array] = []
var _walls: Array[PackedVector2Array] = []
var _sweep := 0.0
var _seen := {} # instance id -> last world XZ while the enemy was on the map
var _ghosts := {} # instance id -> {pos: Vector2 (world XZ), lost: int (ticks ms)}
var player: Player # local pawn; HUD sets this through bind_player


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta / UAV_SWEEP, 1.0)
	_refresh_map()
	queue_redraw()


## Rebuild the outline when a new map scene is under World.
func _refresh_map() -> void:
	var map := _find_map()
	if map == _map_ref.get_ref():
		return
	_map_ref = weakref(map)
	_floors.clear()
	_walls.clear()
	if map == null:
		return
	collect_outline(map, _floors, _walls)


func _find_map() -> Node:
	var main := get_tree().current_scene
	if main and "map_node" in main:
		return main.map_node
	return null


## Top-down footprints of every union CSGBox3D. Low ones (floors, decks, kerbs) go into `floors`,
## tall ones (walls, crates, houses) into `walls`. Corners are world XZ.
static func collect_outline(root: Node, floors: Array[PackedVector2Array], walls: Array[PackedVector2Array]) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var b := n as CSGBox3D
		if b == null or not b.is_inside_tree() or b.operation != CSGShape3D.OPERATION_UNION:
			continue
		var t := b.global_transform
		var h := b.size * 0.5
		var poly := PackedVector2Array()
		for corner in [Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z)]:
			var w: Vector3 = t * corner
			poly.append(Vector2(w.x, w.z))
		var tall := (t.basis * Vector3(0, b.size.y, 0)).length()
		if tall >= 1.5: # floors and decks are about 1 m or less
			walls.append(poly)
		else:
			floors.append(poly)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.07, 0.78))
	var me := player
	if me == null or not is_instance_valid(me):
		_draw_frame(r)
		return
	var origin := Vector2(me.global_position.x, me.global_position.z)
	var yaw := me.global_rotation.y
	var scale_px := r / RANGE
	# World XZ -> map pixels: relative to me, rotated so my look direction (-Z) points up.
	var to_px := func(p: Vector2) -> Vector2:
		return c + to_local_map(p, origin, yaw) * scale_px
	for poly in _floors:
		draw_colored_polygon(_project(poly, to_px), Color(0.2, 0.22, 0.25, 0.9))
	for poly in _walls:
		draw_colored_polygon(_project(poly, to_px), Color(0.55, 0.58, 0.62, 0.9))
	var uav := Game.radar_left > 0.0
	if uav:
		var a := _sweep * TAU
		draw_line(c, c + Vector2(cos(a), sin(a)) * r * 1.5, Color(1, 0.86, 0.35, 0.35), 3.0)
	var now := Time.get_ticks_msec()
	var marks := {}
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p == me:
			continue
		var m := mark_for(p, me, uav, now)
		var wp := Vector2(p.global_position.x, p.global_position.z)
		if m == MARK_FRIEND:
			_draw_arrow(to_px.call(wp), p.global_rotation.y - yaw, 6.0, Player.team_color(p.team_id).lightened(0.25))
		elif m == MARK_ENEMY:
			marks[p.get_instance_id()] = wp
	track_contacts(marks, now)
	for id in _ghosts:
		var g: Dictionary = _ghosts[id]
		_draw_enemy(to_px.call(g.pos), ghost_alpha(int(g.lost), now))
	for id in marks:
		_draw_enemy(to_px.call(marks[id]), 1.0)
	_draw_arrow(c, 0.0, 8.0, Color(1, 0.92, 0.55))
	_draw_frame(r)
	if uav:
		draw_string(get_theme_default_font(), Vector2(6, size.y - 6), "UAV %ds" % ceili(Game.radar_left),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.86, 0.35))


## World XZ relative to `origin`, turned so a pawn with `yaw` looks up (-Y on screen). Metres.
static func to_local_map(p: Vector2, origin: Vector2, yaw: float) -> Vector2:
	return Transform2D(yaw, Vector2.ZERO) * (p - origin)


## `visible`: instance id -> world XZ of enemies shown this frame. Enemies that were shown
## last frame and are not now (UAV over, shot dot expired, died, left) become ghosts at their
## last known spot; ghosts older than FADE_MS go. Seen again: the ghost is dropped.
func track_contacts(visible: Dictionary, now: int) -> void:
	for id in _seen:
		if not visible.has(id):
			_ghosts[id] = {"pos": _seen[id], "lost": now}
	for id in visible:
		_ghosts.erase(id)
	for id in _ghosts.keys():
		if now - int(_ghosts[id].lost) >= FADE_MS:
			_ghosts.erase(id)
	_seen = visible.duplicate()


static func ghost_alpha(lost_ms: int, now: int) -> float:
	return clampf(1.0 - float(now - lost_ms) / FADE_MS, 0.0, 1.0)


func _draw_enemy(pos: Vector2, a: float) -> void:
	if a <= 0.0:
		return
	draw_circle(pos, 5.0, Color(0.95, 0.18, 0.15, a))
	draw_arc(pos, 5.0, 0, TAU, 16, Color(0, 0, 0, 0.8 * a), 1.5)


const MARK_NONE := 0
const MARK_FRIEND := 1
const MARK_ENEMY := 2


## What `p` looks like on `me`'s minimap. Teammates always (not in FFA), enemies only on a
## running UAV or right after they fired.
static func mark_for(p: Player, me: Player, uav: bool, now_ms: int) -> int:
	if p == null or p == me or p.is_dead:
		return MARK_NONE
	if not Game.is_ffa() and p.team_id == me.team_id:
		return MARK_FRIEND
	if uav or now_ms - p.last_shot_ms < SHOT_SHOW_MS:
		return MARK_ENEMY
	return MARK_NONE


func _project(poly: PackedVector2Array, to_px: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = to_px.call(poly[i])
	return out


## Arrow pointing along `rot` (0 = up on the map, matching a pawn facing -Z).
func _draw_arrow(at: Vector2, rot: float, s: float, col: Color) -> void:
	var f := Vector2(0, -1).rotated(-rot)
	var side := Vector2(f.y, -f.x)
	var pts := PackedVector2Array([at + f * s, at - f * s * 0.7 + side * s * 0.7, at - f * s * 0.35, at - f * s * 0.7 - side * s * 0.7])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.85), 1.2)


func _draw_frame(_r: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.86, 0.35, 0.55), false, 2.0)
