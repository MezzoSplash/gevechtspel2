class_name LosOutline
extends CanvasLayer
## #384: while your hands are out, every enemy within RANGE gets a crystal diamond on your screen,
## drawn over the walls: the hands fly faster than a target can be found, so the streak shows you
## where the food is. One inside BASH_PICK_M also gets a ring, the range the bash reaches for.
## Driver only: the server never needs it, and the enemy must not see your marks.
## Purely visual: the server still decides every hit.

const RANGE := 30.0
const BASH_PICK_M := 4.0
const COLOR := Color(0.62, 0.93, 1.0, 0.9)
const COLOR_BASH := Color(1.0, 0.84, 0.42, 1.0)
const DIAMOND := 13.0 # px, half width
const RING := 22.0 # px at bash range

var _view: Control


func _ready() -> void:
	layer = 6
	_view = Control.new()
	_view.name = "Marks"
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.draw.connect(_draw_marks)


func _process(_delta: float) -> void:
	if _view:
		_view.queue_redraw()


## Everyone this machine may mark: living enemies of `me` within `range` of `origin`, nearest first.
## A static so the check can run it headless without a viewport.
static func targets(origin: Vector3, me: Player, range_m: float) -> Array:
	var out: Array = []
	if me == null or not me.is_inside_tree():
		return out
	for n in me.get_tree().get_nodes_in_group("player"):
		var v := n as Player
		if v == null or v == me or v.is_dead or v.is_queued_for_deletion():
			continue
		if not Game.is_enemy(v, me):
			continue
		var d := origin.distance_to(v.global_position)
		if d > range_m:
			continue
		out.append({"p": v, "d": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	return out


func _draw_marks() -> void:
	var me := Game.player_for_peer(Game.multiplayer.get_unique_id())
	var cam := get_viewport().get_camera_3d()
	if me == null or cam == null:
		return
	var origin := me.global_position
	for t in targets(origin, me, RANGE):
		var v := t["p"] as Player
		var point := v.global_position + Vector3.UP * 1.0
		if cam.is_position_behind(point):
			continue
		var at := cam.unproject_position(point)
		var bash := float(t["d"]) <= BASH_PICK_M
		var col := COLOR_BASH if bash else COLOR
		var r := DIAMOND * (1.25 if bash else 1.0)
		var pts := PackedVector2Array([
			at + Vector2(0.0, -r), at + Vector2(r, 0.0), at + Vector2(0.0, r), at + Vector2(-r, 0.0),
		])
		_view.draw_polyline(pts, col, 2.0, true)
		_view.draw_polyline(PackedVector2Array([pts[3], pts[0], pts[1], pts[2], pts[3]]), col, 2.0, true)
		if bash:
			_view.draw_arc(at, RING, 0.0, TAU, 24, col, 2.0, true)
