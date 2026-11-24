class_name WeaponModel
extends RefCounted
## Gun scene helpers shared by the first-person weapon, killcam ghosts and tools (#106): fit and centre a
## model, prepare and play its muzzle flash and its clips, shadows off. Static only; Weapon keeps
## wrappers under the old names. What a gun scene may hold is the artist's contract in
## docs/art/wapens.md; where its files live is WeaponKit:
##   Muzzle         a Marker3D (or plain Node3D) on the barrel's end: tracers leave from there, and
##                  everything under it is the muzzle flash. Particles restart on every shot, meshes,
##                  sprites and lights are shown for the gun's flash_time. "muzzle_flash" is the
##                  older name and still works (the SMG).
##   Sight          optional Marker3D on top of the front sight: aiming lines it up under the eye
##                  (older: a mesh named Front_Sight*).
##   AnimationPlayer optional, clips named fire, reload and draw (any library prefix; a name that ends
##                  in "_fire" counts too). fire plays per shot, reload is stretched to the reload time
##                  and replaces the code's own reload motion of the gun, draw plays when it comes out.

const CLIP_KINDS: Array[StringName] = [&"fire", &"reload", &"draw"]


## Turns shadow casting off for every mesh under `n`.
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
		&"knife", &"shank":
			root = Vector3(0.19, -0.15, -0.30)
			length = 0.25
	var flash_root := muzzle_node(model)
	var aabb := aabb_in_parent(model, flash_root)
	var long := maxf(aabb.size.z, 0.05)
	var s := length / long
	model.scale = Vector3(s, s, s)
	aabb = aabb_in_parent(model, flash_root)
	var center := aabb.get_center()
	model.position -= Vector3(center.x, center.y + 0.02, center.z + length * 0.18)
	aabb = aabb_in_parent(model, flash_root)
	var muzzle_pos := Vector3(0.0, aabb.get_center().y, aabb.position.z)
	# An authored muzzle sits on the barrel. Tracers leave from there instead of the mesh's front.
	if flash_root:
		muzzle_pos = origin_in_parent(model, flash_root)
	var fit := {"root": root, "muzzle": muzzle_pos}
	# Iron sights: top of the front sight in root space, so ADS lines it up under the eye.
	var marker := model.find_child("Sight", true, false) as Node3D
	var sight := model.find_child("Front_Sight*", true, false) as MeshInstance3D
	if marker and not (marker is GeometryInstance3D):
		# #362: the whole point, not only its height: the gun has to line its sight up with the eye, and a
		# sight that sits off the barrel axis (the pistol, the SMG) was pulled to the middle by its y alone.
		var at := origin_in_parent(model, marker)
		fit["sight"] = at
		fit["sight_y"] = at.y
	elif sight and sight.mesh:
		var top := xform_in_parent(model, sight) * sight.mesh.get_aabb()
		fit["sight"] = Vector3(top.get_center().x, top.end.y, top.get_center().z)
		fit["sight_y"] = top.end.y
	return fit


## The muzzle point of a gun scene: a non-mesh node named Muzzle, else the older "muzzle_flash".
## A mesh called Muzzle (the low-poly barrel tips) is part of the gun, not the point. Null: none.
static func muzzle_node(model: Node) -> Node3D:
	var m := model.find_child("Muzzle", true, false) as Node3D
	if m and not (m is GeometryInstance3D):
		return m
	return model.find_child("muzzle_flash", true, false) as Node3D


## The flash's meshes, sprites and lights under the muzzle point: shown for a moment per shot.
## Particles are not in it, they play their own burst.
static func flash_nodes(model: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var root := muzzle_node(model)
	if root == null:
		return out
	for n in root.find_children("*", "Node3D", true, false):
		if (n is GeometryInstance3D or n is Light3D) and not (n is GPUParticles3D or n is CPUParticles3D):
			out.append(n as Node3D)
	return out


## Gets a gun scene ready to be shot: particles are authored as loops, so they are held until a
## shot restarts them (one shot each, local coords so the flash stays on the moving muzzle); clips are
## exported looping, so one shot is one cycle and stops at the end (else the bolt keeps cycling after
## the trigger is let go); the flash's meshes and lights start hidden.
static func prepare_muzzle(model: Node) -> void:
	_prepare_tree(model)
	for n in flash_nodes(model):
		n.visible = false


static func _prepare_tree(model: Node) -> void:
	if model is GPUParticles3D:
		var particles := model as GPUParticles3D
		particles.one_shot = true
		particles.local_coords = true
		particles.emitting = false
	elif model is CPUParticles3D:
		var cpu := model as CPUParticles3D
		cpu.one_shot = true
		cpu.local_coords = true
		cpu.emitting = false
	elif model is AnimationPlayer:
		var ap := model as AnimationPlayer
		ap.stop()
		for clip_name in ap.get_animation_list():
			ap.get_animation(clip_name).loop_mode = Animation.LOOP_NONE
	for child in model.get_children():
		_prepare_tree(child)


## Fire clip plus one muzzle flash. True when the model drew its own flash (particles or flash meshes),
## so the shared quad stays off. `flash_time` is how long the flash meshes and lights stay on.
static func play_model_shot(model: Node3D, playback_speed: float = 1.0, fire_rate: float = 0.0, flash_time: float = 0.045) -> bool:
	if model == null:
		return false
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip_name := fire_clip(anim)
	if anim and clip_name != StringName():
		var clip := anim.get_animation(clip_name)
		# A clip longer than the shot interval is sped up so each shot finishes a cycle,
		# and it follows killcam slow-mo (playback_speed is how fast replay time moves).
		var pace := maxf(playback_speed, 0.01)
		if fire_rate > 0.0 and clip.length > 0.0:
			pace = maxf(pace, clip.length * fire_rate * pace)
		anim.speed_scale = pace
		# play() on the clip that is already running just continues it: stop first, so a held
		# trigger restarts the bolt every round.
		anim.stop()
		anim.play(clip_name)
	var burst := burst_muzzle(model)
	return show_flash(model, flash_time / maxf(playback_speed, 0.01)) or burst


## Shows the flash's meshes and lights for `seconds`, restarting the timer on every shot.
## True when the gun has any.
static func show_flash(model: Node3D, seconds: float) -> bool:
	var nodes := flash_nodes(model)
	if nodes.is_empty():
		return false
	for n in nodes:
		n.visible = true
	var old: Tween = model.get_meta(&"_flash_tween") if model.has_meta(&"_flash_tween") else null
	if old and old.is_valid():
		old.kill()
	var tw := model.create_tween()
	tw.tween_interval(maxf(seconds, 0.01))
	tw.tween_callback(func() -> void:
		for n in nodes:
			if is_instance_valid(n):
				n.visible = false)
	model.set_meta(&"_flash_tween", tw)
	return true


## True when the gun's own flash has a light, so the shared muzzle light stays off.
static func has_own_light(model: Node) -> bool:
	for n in flash_nodes(model):
		if n is Light3D:
			return true
	return false


## The fire clip, or "" (kept for the callers from before the kits).
static func fire_clip(anim: AnimationPlayer) -> StringName:
	return clip(anim, &"fire")


## The clip for `kind` (fire, reload, draw): "kind" or "<library>/kind", else a name ending in
## "_kind" (the SMG's "weapons/weapon_smg_fire"). "" when the gun has none.
static func clip(anim: AnimationPlayer, kind: StringName) -> StringName:
	if anim == null:
		return StringName()
	var tail := "_" + String(kind)
	var loose := StringName()
	for name in anim.get_animation_list():
		var n := String(name)
		var bare := n.get_slice("/", n.get_slice_count("/") - 1)
		if bare == String(kind):
			return name
		if loose == StringName() and bare.ends_with(tail):
			loose = name
	return loose


## True when the gun scene has a clip for `kind`.
static func has_clip(model: Node, kind: StringName) -> bool:
	if model == null:
		return false
	return clip(model.find_child("AnimationPlayer", true, false) as AnimationPlayer, kind) != StringName()


## Plays the clip for `kind`, stretched to `seconds` when that is > 0. False when there is no clip.
static func play_clip(model: Node, kind: StringName, seconds: float = 0.0) -> bool:
	if model == null:
		return false
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var name := clip(anim, kind)
	if name == StringName():
		return false
	var length := anim.get_animation(name).length
	anim.speed_scale = length / seconds if seconds > 0.0 and length > 0.0 else 1.0
	anim.stop()
	anim.play(name)
	return true


## Stops the clip for `kind` if it is the one playing (a reload cut short by a switch or a death).
static func stop_clip(model: Node, kind: StringName) -> void:
	if model == null:
		return
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.is_playing() and anim.current_animation == clip(anim, kind):
		anim.stop()


## Restarts the muzzle particles under `node`; true if it had any.
static func burst_muzzle(node: Node) -> bool:
	var burst := false
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.one_shot = true
		# restart() clears the previous burst and turns emitting on. One shot, then it stops.
		particles.restart()
		burst = true
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		cpu.one_shot = true
		cpu.restart()
		burst = true
	for child in node.get_children():
		if burst_muzzle(child):
			burst = true
	return burst


## `target`'s origin in the space `root` sits in.
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


## Combined mesh bounds of `n` in its parent's space.
## `skip` (the muzzle point) is left out with everything under it: a flash mesh is not the gun.
static func aabb_in_parent(n: Node3D, skip: Node = null) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array = [[n, n.transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if skip != null and node == skip:
			continue
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
