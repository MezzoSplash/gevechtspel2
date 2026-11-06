extends Node
## LINE strips (#B8): the server measures a pawn's speed over the time since its last real position
## snapshot, not over one physics tick. Positions arrive ~30x/s while the server ticks 60x/s, so
## dividing a half-tick of movement by a full tick made a walker read twice as fast and handed out
## strips nobody earned. Also guards that a real surf still measures as one.
##   godot --headless --path . res://tools/check_line_speed.tscn   → "LINE SPEED CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


## One tick of the server loop: a snapshot only lands on every other tick (30 Hz vs 60 Hz ticks).
## Returns the measured speeds; -1 means "no new snapshot, nothing measured".
func _simulate(speed_mps: float, ticks: int) -> Array[float]:
	var out: Array[float] = []
	var prev := Vector3.ZERO
	var prev_ms := 0
	for i in range(1, ticks + 1):
		var now_ms := roundi(float(i) * 1000.0 / 60.0)
		var pos := prev
		if i % 2 == 0:
			pos = Vector3(0.0, 0.0, -speed_mps * float(i) / 60.0)
		var spd := MatchFlow.step_speed(prev, prev_ms, pos, now_ms)
		out.append(spd)
		if spd >= 0.0:
			prev = pos
			prev_ms = now_ms
	return out


func _ready() -> void:
	# No new snapshot: nothing to measure, and the window must keep running.
	_ok(MatchFlow.step_speed(Vector3.ZERO, 1000, Vector3.ZERO, 1016) == -1.0,
		"a tick without a new snapshot measures nothing (-1)")

	# A walk is a walk. The old per-tick division read ~11.4 m/s here.
	var walk := _simulate(5.7, 60)
	var walk_max := 0.0
	var walk_hits := 0
	for v in walk:
		if v >= 0.0:
			walk_hits += 1
			walk_max = maxf(walk_max, v)
	_ok(walk_hits == 30, "one measurement per snapshot, not per tick (%d of 60)" % walk_hits)
	_ok(walk_max < 6.0, "a 5.7 m/s walker never measures above 6 m/s (%.2f)" % walk_max)
	_ok(walk_max > 5.0, "and the walk is actually measured (%.2f m/s)" % walk_max)
	_ok(walk_max < Player.STRIP_SPEED, "a walk cannot cash a strip (%.1f < %.1f)" % [walk_max, Player.STRIP_SPEED])

	# A real surf still reads as one: the fix must not lock players out of the strips.
	var surf := _simulate(Player.CARRY_MAX, 60)
	var surf_max := 0.0
	for v in surf:
		surf_max = maxf(surf_max, v)
	_ok(surf_max > Player.STRIP_SPEED, "a %.0f m/s surf clears STRIP_SPEED (%.1f > %.1f)" % [
		Player.CARRY_MAX, surf_max, Player.STRIP_SPEED])
	_ok(surf_max < Player.CARRY_MAX + 0.5, "and is not overstated (%.2f for %.0f)" % [surf_max, Player.CARRY_MAX])

	print("LINE SPEED CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
