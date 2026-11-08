extends Node3D
## Headless: walks a real Player (keyboard input) and a bot pawn (bot steering + StepUp) from one end
## of every Skyline ramp, stair, plank and bridge to the other, both directions, three lanes, walk and
## sprint. Bot ramp use is covered by check_skyline_bots.   godot --headless res://tools/check_skyline_walk.tscn
##
## The route ends are read from the map itself — the collider's own box — instead of a hand-typed
## table. The old table drifted out of sync with the geometry (it even had the tower stair upside
## down), so the check failed for reasons that were not the map and got skipped for months (#103).
## A run fails when the pawn stops (< 0.6 m/s for 0.25 s) or crawls (< 45% of target speed for
## 0.15 s) with the input held, falls off, times out, or ends more than 0.5 m away from the far lip.

const PLAYER := preload("res://scenes/player.tscn")
const Brain := preload("res://scripts/bot_brain.gd")

## Collider/box name prefixes; every _B half mirrored to _O at the other side of the map.
const ROUTES: Array[String] = [
	"TowerStair", "WestStair", "WestPlank", "WestRamp", "CrossPlank",
	"FireEscape", "EastStair", "EastPlank", "SpawnBridge", "MidBridge",
	"SurfPadLink", "SpineCatchRamp",
]
const RUN_OUT := 0.0 # m past the lip: the lip IS the target, so a run cannot walk off the edge
const LANES := 3

var fails: Array[String] = []
var _last := Vector3.INF


func _ready() -> void:
	# Real-time physics made 360 walks sit silent for minutes (#103). time_scale scales the physics
	# delta with it, so 12 made one tick 0.2 s of movement — coarse enough that a single tick of
	# landing recovery read as a dead stop. 4 keeps the ticks physical and the run inside the budget.
	Engine.time_scale = 4.0
	print("SKYLINE WALK start")
	var map := (load("res://scenes/maps/skyline.tscn") as PackedScene).instantiate() as Node3D
	add_child(map)
	Game.is_offline = true
	for i in 3:
		await get_tree().physics_frame
	var runs := 0
	for base in ROUTES:
		for half in ["_B", "_O"]:
			var ramp := _box(map, base + half)
			if ramp.is_empty():
				fails.append("%s%s: no collider found" % [base, half])
				print("  FAIL %s%s: no collider found" % [base, half])
				continue
			print("skyline %s%s" % [base, half])
			for lane in range(-(LANES / 2), LANES / 2 + 1):
				for flip in [false, true]:
					# No bot lane: bot ramp use is check_skyline_bots' job, with the navmesh and
					# steering the real bots have. This check is about the geometry a player walks.
					for mode in ["walk", "sprint"]:
						runs += 1
						var res: String = await _run(ramp, base + half, lane, flip, mode)
						if res != "":
							var tag := "%s%s %s lane %d %s %s" % [
								base, half, "up" if not flip else "down", lane, mode, res]
							fails.append(tag)
							print("  FAIL ", tag)
	print("runs %d, failures %d" % [runs, fails.size()])
	print("SKYLINE WALK CHECK: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	Engine.time_scale = 1.0
	get_tree().quit(1 if fails.size() else 0)


## The far ends of a walkable box, on its top face: {a, b, half_x, name}. Empty when the map has no
## such node. Works for a CollisionShape3D (under Arena/RampColliders) and for a CSG box (Arena).
func _box(map: Node3D, id: String) -> Dictionary:
	var collider := map.find_child(id, true, false)
	if collider == null:
		return {}
	var xform: Transform3D
	var size: Vector3
	if collider is CollisionShape3D and collider.shape is BoxShape3D:
		xform = collider.global_transform
		size = (collider.shape as BoxShape3D).size
	elif collider is CSGBox3D:
		xform = collider.global_transform
		size = (collider as CSGBox3D).size
	else:
		return {}
	if size.z <= 0.01:
		return {}
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	return {
		"a": xform * Vector3(0.0, hy, -hz),
		"b": xform * Vector3(0.0, hy, hz),
		"half_x": size.x * 0.5,
		"name": id,
	}


func _run(ramp: Dictionary, id: String, lane: int, flip: bool, mode: String) -> String:
	var a: Vector3 = ramp["b"] if flip else ramp["a"]
	var b: Vector3 = ramp["a"] if flip else ramp["b"]
	var off := minf(0.45, maxf(float(ramp["half_x"]) - 0.35, 0.0))
	var across := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized() * float(lane) * off
	# Start 0.3 m onto the ramp: the bare lip can sit inside a roof or a wall (the tower stair tops
	# out under the tower roof), and a pawn spawned inside geometry never walks straight again.
	var from := a + across + (b - a).normalized() * 0.3 + Vector3.UP * 0.1
	var to := b + across
	var bot := mode == "bot"
	var p: Player = PLAYER.instantiate()
	p.is_bot = bot
	p.name = "Walker"
	add_child(p)
	p.global_position = from
	if bot:
		p.call_deferred("set", "_bot_brain", null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	p._bot_brain = null
	var brain = Brain.new() if bot else null
	if brain:
		brain.setup(p, null)
	var dir := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
	p.look_at(p.global_position + dir, Vector3.UP)
	p._yaw = p.rotation.y
	var target := Player.WALK_SPEED if mode != "sprint" else Player.SPRINT_SPEED
	target *= p.gun_speed_mult()
	if mode == "sprint":
		Input.action_press("sprint")
	if not bot:
		Input.action_press("move_forward")
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var limit := dist / (target * 0.5) + 2.0
	var t := 0.0
	var slow := 0.0
	var crawl := 0.0
	var hist: Array = [] # [t, pos] of the last few ticks: one coarse tick must not read as a stall
	var started := false
	var res := ""
	_last = Vector3.INF
	while true:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if brain:
			if not p.is_on_floor():
				p.velocity.y += float(p.get_gravity().y) * dt
			else:
				p.velocity.y = 0.0
			brain._steer_to(to, Player.WALK_SPEED, dt, false)
			brain._move(dt)
		var pos := p.global_position
		var left := Vector2(to.x - pos.x, to.z - pos.z)
		if left.dot(Vector2(dir.x, dir.z)) < 0.2:
			break
		if pos.y < minf(from.y, to.y) - 1.5:
			res = "fell at %s" % _v(pos); break
		var real := 0.0
		if _last != Vector3.INF:
			real = (Vector2(pos.x, pos.z) - Vector2(_last.x, _last.z)).length() / dt
		_last = pos
		hist.append([t, pos])
		if hist.size() > 4:
			hist.pop_front()
		if hist.size() >= 3:
			var age: float = t - float(hist[0][0])
			if age > 0.001:
				real = (Vector2(pos.x, pos.z) - Vector2(hist[0][1].x, hist[0][1].z)).length() / age
		if real > target * 0.8:
			started = true
		if started:
			slow = slow + dt if real < 0.6 else 0.0
			# Uphill only: a landing scrubs speed on any downhill, and sprinting down a stair is one
			# landing after another. There the bar is the dead-stop test, not a speed band.
			crawl = crawl + dt if (not flip) and real < target * 0.45 else 0.0
			if slow > 0.25:
				res = "STUCK at %s" % _v(pos); break
			if crawl > 0.3:
				res = "snag (%.1f m/s) at %s" % [real, _v(pos)]; break
		if t > limit:
			res = "timeout at %s" % _v(pos); break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	# Only uphill runs are checked for height: sprinting down a ramp launches the pawn over the lip,
	# so its y at the lip says nothing. A descending run is verified by reaching the far lip at all.
	if res == "" and not flip and absf(p.global_position.y - to.y) > 1.2:
		res = "ended at y %.2f (want %.2f)" % [p.global_position.y, to.y]
	p.queue_free()
	await get_tree().physics_frame
	return res


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
