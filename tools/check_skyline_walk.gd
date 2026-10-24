extends Node3D
## Headless: walks a real Player (keyboard input) and a bot pawn (bot steering + StepUp) up and
## down every Skyline ramp, stair, plank and bridge, both directions, walk and sprint, three lanes.
## A run fails when the pawn stops (< 0.6 m/s for 0.25 s) or crawls (< 45% of target speed for
## 0.15 s) with the input held, falls off, or times out.   godot --headless res://tools/check_skyline_walk.tscn

const PLAYER := preload("res://scenes/player.tscn")
const Brain := preload("res://scripts/bot_brain.gd")

# name, axis, a0, a1, lo, hi, y_lo, y_hi, run-out before lo / past hi (m)
const RAMPS := [
	["TowerStair", "z", -6.0, -3.0, 21.5, 29.0, 6.0, 12.0, -0.15, 1.4, 9.0],
	["WestStair", "x", 37.2, 40.0, -21.0, -16.0, 9.0, 12.0, 1.5, 1.5],
	["WestPlank", "z", -26.2, -24.0, 22.0, 26.0, 6.0, 9.0, 1.5, 1.5],
	["WestRamp", "z", -27.4, -25.2, 5.0, 9.5, 4.0, 6.0, 1.5, 1.5],
	["CrossPlank", "x", -1.1, 1.1, -18.0, -10.0, 4.0, 6.0, 1.5, 1.5],
	["FireEscape", "z", 15.8, 18.0, 34.0, 27.0, 12.0, 15.0, 1.5, 1.2],
	["EastStair", "z", 19.0, 21.4, 14.0, 24.0, 9.0, 15.0, 1.5, 1.5],
	["EastPlank", "x", 8.0, 10.0, 10.0, 17.0, 6.0, 9.0, 1.5, 1.5],
	["SpawnBridge", "z", -1.25, 1.25, 36.0, 31.0, 12.0, 12.0, 0.8, 1.5, 9.0],
	["MidBridge", "z", -3.0, 3.0, 10.0, 20.0, 6.0, 6.0, 1.5, 1.2, 0.9],
]

var fails: Array[String] = []
var _drive: Callable


func _ready() -> void:
	var map := (load("res://scenes/maps/skyline.tscn") as PackedScene).instantiate() as Node3D
	add_child(map)
	Game.is_offline = true
	for i in 3:
		await get_tree().physics_frame
	var runs := 0
	for r in RAMPS:
		for half in [1.0, -1.0]:
			for lane in [-1, 0, 1]:
				for up in [true, false]:
					for mode in ["walk", "sprint", "bot"]:
						runs += 1
						var res: String = await _run(r, half, lane, up, mode)
						if res != "":
							var tag := "%s_%s %s lane %d %s %s" % [r[0], "B" if half > 0 else "O", "up" if up else "down", lane, mode, res]
							fails.append(tag)
							print("  FAIL ", tag)
	print("runs %d, failures %d" % [runs, fails.size()])
	print("SKYLINE WALK CHECK: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	get_tree().quit(1 if fails.size() else 0)


func _pt(r: Array, half: float, across: float, along: float, y: float) -> Vector3:
	var p := Vector3(across, y, along) if r[1] == "z" else Vector3(along, y, across)
	return Vector3(p.x * half, p.y, p.z * half)


func _run(r: Array, half: float, lane: int, up: bool, mode: String) -> String:
	var a0: float = r[2]; var a1: float = r[3]; var lo: float = r[4]; var hi: float = r[5]
	var s := signf(hi - lo)
	var mid := (a0 + a1) * 0.5
	var off := minf(absf(a1 - a0) * 0.5 - 0.5, r[10] if r.size() > 10 else 9.0)
	var across := mid + lane * off
	var bottom := _pt(r, half, across, lo - s * r[8], r[6])
	var top := _pt(r, half, across, hi + s * r[9], r[7])
	var from := bottom if up else top
	var to := top if up else bottom
	var bot := mode == "bot"
	var p: Player = PLAYER.instantiate()
	p.is_bot = bot
	p.name = "Walker"
	add_child(p)
	p.global_position = from + Vector3(0, 0.05, 0)
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
	var limit := dist / (target * 0.5) + 1.5
	var t := 0.0
	var slow := 0.0
	var crawl := 0.0
	var started := false
	var res := ""
	var worst := INF
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
		if pos.y < minf(from.y, to.y) - 1.0:
			res = "fell at %s" % _v(pos); break
		var sp := Vector2(p.velocity.x, p.velocity.z).dot(Vector2(dir.x, dir.z))
		var real := (Vector2(pos.x, pos.z) - Vector2(_last.x, _last.z)).length() / dt if _last != Vector3.INF else sp
		_last = pos
		if real > target * 0.8:
			started = true
		if started:
			worst = minf(worst, real)
			slow = slow + dt if real < 0.6 else 0.0
			crawl = crawl + dt if real < target * 0.45 else 0.0
			if slow > 0.25:
				res = "STUCK at %s" % _v(pos); break
			if crawl > 0.15:
				res = "snag (%.1f m/s) at %s" % [real, _v(pos)]; break
		if t > limit:
			res = "timeout at %s" % _v(pos); break
	_last = Vector3.INF
	Input.action_release("move_forward")
	Input.action_release("sprint")
	if res == "" and absf(p.global_position.y - to.y) > 0.4:
		res = "ended at y %.2f (want %.1f)" % [p.global_position.y, to.y]
	p.queue_free()
	await get_tree().physics_frame
	return res

var _last := Vector3.INF

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
