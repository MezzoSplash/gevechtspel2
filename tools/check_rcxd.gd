extends Node3D
## Scripted RC-XD drive on a test yard (flat floor, a wall, a kicker ramp). Headless:
##   godot --headless --path . res://tools/check_rcxd.tscn -- out=/tmp/rcxd.csv
## Writes t,run,x,y,z,speed,heading,yaw_rate,on_floor per physics tick and prints a summary.
## Uses only apply_remote_input(), so the same script drives any version of the car.

var out := "/tmp/rcxd.csv"
var rows: PackedStringArray = []
var fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	_run.call_deferred()


func _box(pos: Vector3, size: Vector3, rot_x := 0.0) -> void:
	_box_basis(pos, Basis(Vector3.RIGHT, rot_x), size)


func _box_basis(pos: Vector3, basis: Basis, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	s.shape = shape
	b.add_child(s)
	add_child(b)
	b.global_transform = Transform3D(basis, pos)


func _run() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400))          # floor, top at y 0
	_box(Vector3(0, 1.5, -60), Vector3(20, 3, 1))            # wall 60 m ahead of run 2
	# Kicker for run 3: 3.2 m long at 18 deg, lip at about 1 m, then flat floor again.
	_box(Vector3(40, 0.0, -10.0), Vector3(4, 0.4, 3.4), deg_to_rad(18.0))
	for i in 4:
		await get_tree().physics_frame
	# run 1: launch, 90 deg turn at speed, coast, brake into reverse
	await _drive(1, Vector3(0, 0.3, 0), [
		[2.0, 0.0, 1.0], [1.5, PI * 0.5, 1.0], [1.0, PI * 0.5, 0.0], [1.5, PI * 0.5, -1.0]])
	# run 2: full throttle into the wall
	await _drive(2, Vector3(0, 0.3, -40), [[3.0, 0.0, 1.0]])
	# run 3: off the kicker
	await _drive(3, Vector3(40, 0.3, 8), [[3.0, 0.0, 1.0]])
	# run 4: full throttle down a 30° ramp. The floor flatten used to leave the
	# uphill part of the ground stick behind, so this crawl stayed under 1 m/s.
	var angle := deg_to_rad(30.0)
	var basis := Basis(Vector3(-1, 0, 0), Vector3(0, cos(angle), sin(angle)), Vector3(0, sin(angle), -cos(angle)))
	var length := 24.0
	var low := Vector3(70, 0, 0)
	var mid := low + basis.z * (length * 0.5) - basis.y * 0.2
	_box_basis(mid, basis, Vector3(6.0, 0.4, length))
	await _drive(4, low + basis.z * 14.0 + basis.y * 0.6, [[1.8, PI, 1.0]], PI)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_line("t,run,x,y,z,speed,heading,yaw_rate,on_floor")
	for r in rows:
		f.store_line(r)
	f.close()
	print("RCXD CHECK %s (%d failures) -> %s" % ["OK" if fails == 0 else "FAILED", fails, out])
	get_tree().quit(1 if fails else 0)


func _drive(run: int, start: Vector3, plan: Array, yaw_in := 0.0) -> void:
	var car := RcXd.new()
	car.authority_sim = true
	car.owner_peer = -99
	car.net_id = 9000 + run
	car.yaw = yaw_in
	add_child(car)
	car.global_position = start
	car.life = 999.0
	var t := 0.0
	var last_h := car.rotation.y
	var max_speed := 0.0
	var max_y := 0.0
	var air := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for step in plan:
		var left: float = step[0]
		while left > 0.0:
			car.apply_remote_input(step[1], step[2])
			await get_tree().physics_frame
			if not is_instance_valid(car):
				_fail("run %d: car freed" % run)
				return
			t += dt
			left -= dt
			var hv := Vector3(car.velocity.x, 0, car.velocity.z).length()
			var h := car.rotation.y
			var rate := wrapf(h - last_h, -PI, PI) / dt
			last_h = h
			max_speed = maxf(max_speed, hv)
			max_y = maxf(max_y, car.global_position.y)
			if not car.is_on_floor():
				air += dt
			var p := car.global_position
			rows.append("%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.4f,%.3f,%d" % [t, run, p.x, p.y, p.z, hv, h, rate, int(car.is_on_floor())])
	var end_speed := Vector3(car.velocity.x, 0, car.velocity.z).length()
	print("run %d: max speed %.2f m/s, end speed %.2f, max y %.2f, airtime %.2f s, end pos %s" % [
		run, max_speed, end_speed, max_y, air, car.global_position])
	if max_speed < 5.0:
		_fail("run %d: never got going" % run)
	if run == 4 and max_speed < 8.0:
		_fail("run %d: ramp cut speed to %.2f m/s" % [run, max_speed])
	if car.global_position.y < -1.0:
		_fail("run %d: fell through the floor" % run)
	car.shutdown(false)
	for i in 3:
		await get_tree().physics_frame


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL ", msg)
