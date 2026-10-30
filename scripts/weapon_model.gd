class_name WeaponModel
extends RefCounted
## Gun GLB helpers shared by the first-person weapon, killcam ghosts and tools (#106): fit and centre a
## model, prepare and play its muzzle burst and fire clip, shadows off. Static only; Weapon keeps
## wrappers under the old names.


static func no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		no_shadows(c)


## Scales and centres a gun GLB for this slot. Returns where the gun root sits under the camera
## ("root") and the muzzle in root space ("muzzle"). The killcam ghosts use the same numbers.
static func fit_model(model: Node3D, id: StringName, rest_pos: Vector3) -> Dictionary:
	# GLBs are modeled along +X; +90 Y puts the muzzle down camera -Z.
	model.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	model.position = Vector3.ZERO
	model.scale = Vector3.ONE
	var root := Vector3(rest_pos.x, rest_pos.y, rest_pos.z + 0.06)
	var length := 0.42
	match id:
		&"pistol":
			root = Vector3(0.20, -0.16, -0.26)
			length = 0.30
		&"shotgun":
			root = Vector3(0.22, -0.18, -0.30)
			length = 0.50
		&"sniper":
			root = Vector3(0.22, -0.17, -0.28)
			length = 0.58
		&"smg":
			root = Vector3(0.21, -0.17, -0.27)
			length = 0.40
		&"revolver":
			root = Vector3(0.19, -0.15, -0.30)
			length = 0.30
		&"lmg":
			root = Vector3(0.23, -0.19, -0.30)
			length = 0.62
		&"slug":
			root = Vector3(0.22, -0.18, -0.30)
			length = 0.54
		&"knife":
			root = Vector3(0.19, -0.15, -0.30)
			length = 0.25
	var aabb := aabb_in_parent(model)
	var long := maxf(aabb.size.z, 0.05)
	var s := length / long
	model.scale = Vector3(s, s, s)
	aabb = aabb_in_parent(model)
	var center := aabb.get_center()
	model.position -= Vector3(center.x, center.y + 0.02, center.z + length * 0.18)
	aabb = aabb_in_parent(model)
	var muzzle_pos := Vector3(0.0, aabb.get_center().y, aabb.position.z)
	# A authored muzzle sits on the barrel. Tracers leave from there instead of the mesh centre.
	var flash := model.find_child("muzzle_flash", true, false) as Node3D
	if flash:
		muzzle_pos = origin_in_parent(model, flash)
	var fit := {"root": root, "muzzle": muzzle_pos}
	# Iron sights: top of the front sight in root space, so ADS lines it up under the eye.
	var sight := model.find_child("Front_Sight*", true, false) as MeshInstance3D
	if sight and sight.mesh:
		fit["sight_y"] = (xform_in_parent(model, sight) * sight.mesh.get_aabb()).end.y
	return fit


## The SMG particles are authored as a loop. Hold them until a shot restarts the burst.
## Local coords keep the flash on the muzzle while the viewmodel moves with the camera.
## The fire clip is exported looping too: one shot is one cycle, so it must stop at the end
## (else the bolt keeps cycling after the trigger is let go).
static func prepare_muzzle(model: Node) -> void:
	if model is GPUParticles3D:
		var particles := model as GPUParticles3D
		particles.one_shot = true
		particles.local_coords = true
		particles.emitting = false
	elif model is AnimationPlayer:
		var ap := model as AnimationPlayer
		ap.stop()
		for clip_name in ap.get_animation_list():
			ap.get_animation(clip_name).loop_mode = Animation.LOOP_NONE
	for child in model.get_children():
		prepare_muzzle(child)


## Fire clip plus one muzzle burst. True when the model drew its own flash, so the shared quad stays off.
static func play_model_shot(model: Node3D, playback_speed: float = 1.0, fire_rate: float = 0.0) -> bool:
	if model == null:
		return false
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip_name := fire_clip(anim)
	if anim and clip_name != StringName():
		var clip := anim.get_animation(clip_name)
		# The clip is longer than the SMG interval. Speed it so each shot finishes a cycle,
		# and follow killcam slow-mo (playback_speed is how fast replay time moves).
		var pace := maxf(playback_speed, 0.01)
		if fire_rate > 0.0 and clip.length > 0.0:
			pace = maxf(pace, clip.length * fire_rate * pace)
		anim.speed_scale = pace
		# play() on the clip that is already running just continues it: stop first, so a held
		# trigger restarts the bolt every round.
		anim.stop()
		anim.play(clip_name)
	return burst_muzzle(model)


## Library clips are "weapons/weapon_smg_fire". A bare name only works in the default library.
static func fire_clip(anim: AnimationPlayer) -> StringName:
	if anim == null:
		return StringName()
	if anim.has_animation(&"weapons/weapon_smg_fire"):
		return &"weapons/weapon_smg_fire"
	if anim.has_animation(&"weapon_smg_fire"):
		return &"weapon_smg_fire"
	return StringName()


static func burst_muzzle(node: Node) -> bool:
	var burst := false
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.one_shot = true
		# restart() clears the previous burst and turns emitting on. One shot, then it stops.
		particles.restart()
		burst = true
	for child in node.get_children():
		if burst_muzzle(child):
			burst = true
	return burst


static func origin_in_parent(root: Node3D, target: Node3D) -> Vector3:
	return xform_in_parent(root, target).origin


## `target`'s transform in the space `root` sits in.
static func xform_in_parent(root: Node3D, target: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var node: Node = target
	while node != root and node is Node3D:
		xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return root.transform * xf


static func aabb_in_parent(n: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array = [[n, n.transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh:
				var a := xf * mi.mesh.get_aabb()
				if not has:
					acc = a
					has = true
				else:
					acc = acc.merge(a)
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
			else:
				stack.append([c, xf])
	return acc if has else AABB(Vector3.ZERO, Vector3.ONE)
