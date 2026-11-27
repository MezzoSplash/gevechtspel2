extends Node
## #320: the wallrun's light edge. It has to sit on the side of the wall (left or right of the view),
## follow the time left, fade out just before the run ends, and be off outside a wallrun, when dead, and
## with the speed-effects switch (Access tab) off.
##   ./run.sh --headless res://tools/check_wall_edge.tscn   → "WALL EDGE CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _pawn() -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	return p


## Draait een tick met de opgegeven wallrun-stand en geeft (zijde, sterkte) terug.
func _edge(overlay: HudOverlay, p: Player, running: bool, normal: Vector3, t: float, dead := false) -> Vector2:
	p._wallrunning = running
	p._wall_n = normal
	p._wallrun_t = t
	p.is_dead = dead
	overlay.tick(1.0 / 60.0)
	return Vector2(float(overlay.wall_edge_side), overlay.wall_edge_amt)


func _ready() -> void:
	var old_fx: bool = Game.speed_fx
	var p := _pawn()
	# De camera van de pop kijkt naar -Z, dus zijn rechterkant is +X.
	var overlay := HudOverlay.new()
	add_child(overlay)
	overlay.player = p
	_ok(p.camera != null, "the pawn has a camera")

	# 1) Muur links: de normaal wijst naar rechts (+X).
	var left := _edge(overlay, p, true, Vector3(1, 0, 0), 0.3)
	_ok(left.x == -1.0, "a wall on the left puts the edge on the left (side %.0f)" % left.x)
	_ok(left.y > 0.5, "and it glows while there is time left (%.2f)" % left.y)

	# 2) Muur rechts.
	var right := _edge(overlay, p, true, Vector3(-1, 0, 0), 0.3)
	_ok(right.x == 1.0, "a wall on the right puts the edge on the right (side %.0f)" % right.x)

	# 3) Vlak voor het eind trekt de rand weg, aan het begin komt hij op.
	var nearly_done := _edge(overlay, p, true, Vector3(1, 0, 0), Player.WALLRUN_TIME - 0.05)
	_ok(nearly_done.y < 0.35 and nearly_done.y > 0.0, "the edge fades out before the run ends (%.2f)" % nearly_done.y)
	var just_started := _edge(overlay, p, true, Vector3(1, 0, 0), 0.01)
	_ok(just_started.y < 0.5, "and comes in over the first frames (%.2f)" % just_started.y)

	# 4) Overdrive-wallruns lopen niet af: daar blijft de rand staan.
	var saved := Overdrive.active(p)
	_ok(not saved, "no Overdrive buff in this check, so the run times out")

	# 5) Uit buiten een wallrun, bij een dode speler, en met de speed-effects-schakelaar uit.
	_ok(_edge(overlay, p, false, Vector3(1, 0, 0), 0.3).x == 0.0, "no edge outside a wallrun")
	_ok(_edge(overlay, p, true, Vector3(1, 0, 0), 0.3, true).x == 0.0, "no edge on a dead player")
	Game.speed_fx = false
	_ok(_edge(overlay, p, true, Vector3(1, 0, 0), 0.3).x == 0.0, "the Access-tab switch turns it off")
	Game.speed_fx = old_fx

	# 6) Een muur recht voor of achter heeft geen kant: liever geen rand dan een verkeerde.
	_ok(_edge(overlay, p, true, Vector3(0, 0, -1), 0.3).x == 0.0, "a wall straight ahead has no side")

	print("WALL EDGE CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
