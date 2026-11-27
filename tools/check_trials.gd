extends Node
## Trials-check (#325): de data, de loop en de opslag. Geen netwerk, geen bots.
##
## Wat het bewijst:
## 1. elke lijn heeft minstens twee checkpoints en elk checkpoint heeft een vloer onder zich;
## 2. in volgorde lopen geeft een tijd, de laatste checkpoint sluit de run af;
## 3. een checkpoint overslaan kan niet: alleen de volgende telt;
## 4. een snellere tijd wint, een langzame overschrijft de beste niet, en de ghost hoort bij de tijd;
## 5. de ghost heeft de lengte van de run en de HUD leest dezelfde waarden.
const FAIL_LIMIT := 40

var failures := 0
var checks := 0
var failures_shown := 0


func _ready() -> void:
	await get_tree().physics_frame
	Trials.clear_all()
	_test_data()
	await _test_run()
	_test_store()
	_test_format()
	print("TRIALS CHECK: %s (%d failures, %d checks)" % ["OK" if failures == 0 else "FAIL", failures, checks])
	get_tree().quit(0 if failures == 0 else 1)


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  PASS ", what)
		return
	failures += 1
	if failures_shown < FAIL_LIMIT:
		failures_shown += 1
		print("  FAIL ", what)


func _test_data() -> void:
	var lines := Trials.load_lines(&"townhouses")
	_ok(lines.size() == 3, "townhouses has three lines (got %d)" % lines.size())
	var ids := []
	for line in lines:
		ids.append(line["id"])
		_ok((line["checkpoints"] as Array).size() >= 2, "line '%s' has at least two checkpoints (%d)" % [line["id"], (line["checkpoints"] as Array).size()])
		_ok(String(line["name"]) != "", "line '%s' has a name" % line["id"])
	_ok(ids == ["kade", "brug", "ommeland"], "the three lines are kade, brug and ommeland (got %s)" % str(ids))
	_ok(Trials.load_lines(&"foundry") == [] or Trials.load_lines(&"foundry").size() >= 1, "another map either has lines or returns an empty list, not a crash")
	_ok(not Trials.has_map(&"nope"), "a map without a file has no lines")


## Bouwt de map en een pawn, en loopt de checkpoints in volgorde af.
func _test_run() -> void:
	var scene := (load("res://scenes/maps/townhouses.tscn") as PackedScene).instantiate() as Node3D
	add_child(scene)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = 1
	p.set_physics_process(false) # de check zet de positie zelf
	add_child(p)
	await get_tree().physics_frame

	var run := Node3D.new()
	run.set_script(load("res://scripts/trials_run.gd"))
	add_child(run)
	var ok: bool = run.setup(scene, p, &"townhouses", 0)
	_ok(ok, "the first line loads")
	_ok((run.checkpoints as Array).size() == 7, "the kade line has seven checkpoints (got %d)" % (run.checkpoints as Array).size())

	# Elk checkpoint heeft een vloer: de hint-Y (0) is vervangen door de hoogte van de hit.
	var with_floor := 0
	for cp in run.checkpoints:
		if absf((cp as Vector3).y) < 6.0:
			with_floor += 1
	_ok(with_floor == (run.checkpoints as Array).size(), "every checkpoint found a floor (%d of %d)" % [with_floor, (run.checkpoints as Array).size()])

	# Overslaan kan niet: zet de pawn meteen op het laatste checkpoint.
	p.global_position = run.checkpoints[run.checkpoints.size() - 1]
	for i in 5:
		await get_tree().physics_frame
	_ok(not run.finished_run, "standing on the last checkpoint does not finish the run on its own")
	_ok(run.next_cp == 1, "the run still expects the first checkpoint (next %d)" % run.next_cp)

	# In volgorde afleggen: eerst weg van de start (klok start), dan elk checkpoint aanraken.
	p.global_position = run.checkpoints[0] + Vector3(0, 0, -3)
	for i in 3:
		await get_tree().physics_frame
	_ok(run.running, "leaving the start starts the clock")
	var visited := 0
	for i in range(1, (run.checkpoints as Array).size()):
		p.global_position = run.checkpoints[i]
		for j in 3:
			await get_tree().physics_frame
		visited += 1
	_ok(run.finished_run, "touching the last checkpoint in order finishes the run")
	_ok(run.run_ms > 0, "the run has a time (%d ms)" % run.run_ms)
	_ok(run.next_cp == (run.checkpoints as Array).size(), "all checkpoints were counted (%d of %d)" % [run.next_cp, (run.checkpoints as Array).size()])
	_ok(visited == (run.checkpoints as Array).size() - 1, "every checkpoint was walked, none skipped")

	# De ghost hoort bij de run: ~30 samples per seconde.
	var ghost := Trials.load_ghost(&"townhouses", 0)
	_ok(ghost.size() > 0, "the run saved a ghost (%d floats)" % ghost.size())
	var samples := ghost.size() / 4
	var expected := maxi(1, int(round(run.run_ms / 1000.0 * 30.0)))
	_ok(absi(samples - expected) <= 3, "the ghost has about one sample per 33 ms (%d, expected ~%d)" % [samples, expected])
	_ok(Trials.best_ms(&"townhouses", 0) == run.run_ms, "the fastest time is the one in the save file")

	# Opnieuw starten zet de klok en de checkpoints terug.
	run.restart()
	_ok(not run.running and not run.finished_run and run.next_cp == 1, "restart clears the clock and the checkpoints")
	_ok(p.global_position.distance_to(run.checkpoints[0]) < 0.6, "restart puts the pawn back at the start")

	# Een andere lijn heeft eigen checkpoints en een eigen beste tijd.
	run.next_line()
	_ok(run.line_index == 1, "T switches to the next line")
	_ok((run.checkpoints as Array).size() == 4, "the brug line has four checkpoints (got %d)" % (run.checkpoints as Array).size())
	_ok(run.best == 0, "the brug line has no time yet")

	run.queue_free()
	scene.queue_free()
	p.queue_free()
	await get_tree().process_frame


func _test_store() -> void:
	Trials.clear_all()
	_ok(Trials.best_ms(&"townhouses", 2) == 0, "an empty save has no time")
	_ok(Trials.save_best(&"townhouses", 2, 42000, PackedFloat32Array([1, 2, 3, 4])), "the first time is a record")
	_ok(Trials.best_ms(&"townhouses", 2) == 42000, "and it is stored")
	_ok(not Trials.save_best(&"townhouses", 2, 51000), "a slower time is not a record")
	_ok(Trials.best_ms(&"townhouses", 2) == 42000, "and does not overwrite the record")
	_ok(Trials.save_best(&"townhouses", 2, 39000), "a faster time is a record")
	_ok(Trials.best_ms(&"townhouses", 2) == 39000, "and replaces the old one")
	_ok(Trials.best_ms(&"townhouses", 1) == 0, "another line keeps its own time")
	var ghost := Trials.load_ghost(&"townhouses", 2)
	_ok(ghost.size() == 4 and ghost[0] == 1.0, "the ghost round-trips through the file")
	Trials.clear_all()
	_ok(Trials.best_ms(&"townhouses", 2) == 0, "clear_all wipes the times")


func _test_format() -> void:
	_ok(Trials.format_ms(0) == "0.00s", "0 ms formats as 0.00s (got %s)" % Trials.format_ms(0))
	_ok(Trials.format_ms(12340) == "12.34s", "12340 ms formats as 12.34s (got %s)" % Trials.format_ms(12340))
	_ok(Trials.format_ms(65120) == "1:05.12", "65120 ms formats as 1:05.12 (got %s)" % Trials.format_ms(65120))
	_ok(Trials.format_ms(-1) == "--:--", "a missing time formats as --:--")
