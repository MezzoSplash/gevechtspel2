extends Node

const _Killcam := preload("res://scripts/killcam.gd")


func _ready() -> void:
	await get_tree().process_frame
	var fails := 0
	fails += _check_scene_flags()
	fails += _check_smg()
	fails += _check_rc()
	print("FAILS ", fails)
	get_tree().quit(fails)


func _check_scene_flags() -> int:
	var root := (load("res://assets/weapons/smg/muzzle_flash.tscn") as PackedScene).instantiate()
	var bad := 0
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		print("scene ", p.name, " emitting ", p.emitting, " one_shot ", p.one_shot)
		if p.emitting or not p.one_shot:
			bad += 1
	root.free()
	return bad


func _check_smg() -> int:
	var model := (load("res://assets/weapons/smg/weapon_smg.tscn") as PackedScene).instantiate() as Node3D
	add_child(model)
	Weapon.prepare_muzzle(model)
	var idle := 0
	for n in model.find_children("*", "GPUParticles3D", true, false):
		if (n as GPUParticles3D).emitting:
			idle += 1
	var fit: Dictionary = Weapon.fit_model(model, &"smg", Vector3(0.24, -0.18, -0.42))
	var muzzle: Vector3 = fit.muzzle
	var aabb := _aabb(model)
	print("fit muzzle ", muzzle, " aabb z ", aabb.position.z, " .. ", aabb.position.z + aabb.size.z)
	var flashed: bool = Weapon.play_model_shot(model, 1.0, 20.0)
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var emitting := 0
	for n in model.find_children("*", "GPUParticles3D", true, false):
		if (n as GPUParticles3D).emitting:
			emitting += 1
	print("flashed ", flashed, " playing ", anim.is_playing(), " anim ", anim.current_animation, " speed ", anim.speed_scale, " emitting ", emitting, " idle_was ", idle)
	var bad := 0
	if idle != 0:
		bad += 1
	if not flashed or emitting != 4:
		bad += 1
	if not anim.is_playing() or not String(anim.current_animation).ends_with("weapon_smg_fire"):
		bad += 1
	if absf(anim.speed_scale - 0.083333336 * 20.0) > 0.05:
		bad += 1
	if muzzle.z > aabb.position.z + aabb.size.z * 0.25:
		bad += 1
	var flash := model.find_child("muzzle_flash", true, false) as Node3D
	var fwd := (model.global_transform * flash.transform).basis.z.normalized()
	print("flash forward ", fwd)
	if fwd.z > -0.5:
		bad += 1
	# Second shot must restart a burst that had already been turned off.
	for n in model.find_children("*", "GPUParticles3D", true, false):
		(n as GPUParticles3D).emitting = false
	if not Weapon.play_model_shot(model, 0.25, 20.0):
		bad += 1
	print("slow speed ", anim.speed_scale)
	if absf(anim.speed_scale - 0.083333336 * 20.0 * 0.25) > 0.05:
		bad += 1
	model.queue_free()
	return bad


func _check_rc() -> int:
	var car := RcXd.new()
	car.owner_team = 0
	add_child(car)
	var body := car.get_node("Tilt/Body") as Node3D
	var front := body.find_child("Front_Axle_001", true, false) as Node3D
	var rear := body.find_child("Rear_Axle_001", true, false) as Node3D
	var bounds := _aabb(body)
	print("rc front z ", front.global_position.z, " rear z ", rear.global_position.z)
	print("rc bounds y ", bounds.position.y, " .. ", bounds.position.y + bounds.size.y, " size ", bounds.size)
	var tilt := car.get_node("Tilt") as Node3D
	var mark := tilt.get_child(tilt.get_child_count() - 1) as MeshInstance3D
	print("mark y ", mark.position.y)
	var bad := 0
	if front.global_position.z >= -0.05:
		bad += 1
	if rear.global_position.z <= front.global_position.z:
		bad += 1
	if absf(bounds.size.z - 1.1) > 0.05:
		bad += 1
	if absf(bounds.position.y - (-0.45 * 0.5)) > 0.02:
		bad += 1
	if mark.position.y < bounds.position.y + bounds.size.y - 0.08:
		bad += 1
	car.queue_free()
	return bad


func _aabb(n: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array = [[n, n.global_transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var a: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			acc = a if not has else acc.merge(a)
			has = true
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
			else:
				stack.append([c, xf])
	return acc
