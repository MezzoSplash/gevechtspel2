class_name KillcamPuppets
extends RefCounted
## The replay scene (#317 stap 2, uit scripts/killcam.gd): de ghost-poppen met hun wapen en geluid, de
## granaten en messen uit de snapshots, de tracers en het tijdelijk verbergen van de live wereld.
## Static op de Killcam-node; de nodes (_ghosts, _nades, _knives, _cam, _rest, _hidden) blijven daar en
## dit wordt met de node als `k` aangeroepen.
static func build_ghosts(k: Killcam, killer: int) -> void:
	k._cam = null
	var scene := k.get_tree().current_scene
	var packed := load("res://scenes/player.tscn") as PackedScene
	if scene == null or packed == null:
		return
	var tmpl := packed.instantiate()
	var body_src := tmpl.get_node("BodyMesh") as Node3D
	var tag_src := tmpl.get_node("Nametag") as Label3D
	var weapon_root := tmpl.get_node("Head/Camera3D/WeaponRoot") as Node3D
	k._rest = weapon_root.position
	var fx_src: Array[Node3D] = [
		tmpl.get_node("Head/Camera3D/WeaponRoot/Muzzle/Flash") as Node3D,
		tmpl.get_node("Head/Camera3D/WeaponRoot/Muzzle/FlashLight") as Node3D,
	]
	var mats: Array[StandardMaterial3D] = []
	var torso := body_src.get_node("Torso") as MeshInstance3D
	for team in 2:
		var src := torso.get_surface_override_material(0) as StandardMaterial3D
		var mat := src.duplicate() as StandardMaterial3D if src else StandardMaterial3D.new()
		Player.paint_body(mat, team)
		mats.append(mat)
	var ids := {}
	for f in k._clip.frames:
		for id in (f[1] as Dictionary):
			ids[id] = true
	var info: Dictionary = k._clip.info
	for id in ids:
		var meta: Array = k._clip.meta.get(id, ["", 0])
		var team := clampi(int(meta[1]), 0, 1)
		var g := make_ghost(k, scene, body_src, fx_src, mats[team], id == killer)
		k._ghosts[id] = g
		if id == killer:
			k._cam = g.pivot as Camera3D
		if id == int(info.get("v", 0)):
			var tag := tag_src.duplicate() as Label3D
			tag.text = str(info.get("vn", meta[0]))
			tag.modulate = Player.team_color(int(info.get("vt", team)))
			tag.no_depth_test = true
			tag.visible = true
			(g.root as Node3D).add_child(tag)
	tmpl.free()
	for i in 4:
		var nade := GrenadeLook.new() # the same crystal frag as the match (#342); no fuse is recorded
		nade.visible = false
		scene.add_child(nade)
		k._nades.append(nade)
	for i in 4:
		var knife := Node3D.new()
		var model := Weapon.knife_scene().instantiate() as Node3D
		model.rotation_degrees = Vector3(0.0, 90.0, 0.0) # same as ThrowingKnife: tip down -Z
		model.scale = Vector3.ONE * 1.25
		Weapon.no_shadows(model)
		knife.add_child(model)
		knife.visible = false
		scene.add_child(knife)
		k._knives.append(knife)





static func make_ghost(k: Killcam, scene: Node, body_src: Node3D, fx_src: Array[Node3D], mat: StandardMaterial3D, is_killer: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "KillcamGhost"
	scene.add_child(root, true)
	var body := body_src.duplicate() as Node3D
	for c in body.get_children():
		var part := c as MeshInstance3D
		if part:
			part.set_surface_override_material(0, mat)
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.visible = not is_killer # first person: no own body, like the live game
	root.add_child(body)
	var head := Node3D.new()
	head.position.y = Player.STAND_EYE
	root.add_child(head)
	var pivot: Node3D
	if is_killer:
		var cam := Camera3D.new()
		cam.fov = Game.fov # hip FOV from settings; this replay camera does not zoom
		cam.near = 0.03
		pivot = cam
	else:
		pivot = Node3D.new()
	head.add_child(pivot)
	var gun_root := Node3D.new()
	pivot.add_child(gun_root)
	var muzzle := Node3D.new()
	gun_root.add_child(muzzle)
	# The pawn's own muzzle flash and light, shown together for FLASH_LIFE.
	var flash := Node3D.new()
	flash.visible = false
	muzzle.add_child(flash)
	for src in fx_src:
		var fx := src.duplicate() as Node3D
		fx.position = Vector3.ZERO
		fx.visible = true
		flash.add_child(fx)
	var sfx := AudioStreamPlayer3D.new()
	sfx.bus = "SFX"
	sfx.volume_db = -6.0
	sfx.unit_size = 12.0
	sfx.max_distance = 110.0
	sfx.attenuation_filter_cutoff_hz = 4000.0
	sfx.max_polyphony = 6
	head.add_child(sfx)
	return {
		"root": root, "body": body, "head": head, "pivot": pivot, "gun_root": gun_root,
		"muzzle": muzzle, "flash": flash, "sfx": sfx, "model": null, "wpn": -1, "flash_t": 0.0,
	}





static func ghost_weapon(k: Killcam, g: Dictionary, index: int) -> void:
	index = clampi(index, 0, Weapon.LOADOUT.size() - 1)
	if int(g.wpn) == index:
		return
	g.wpn = index
	if g.model != null and is_instance_valid(g.model):
		(g.model as Node).queue_free()
	var def: WeaponDef = Weapon.LOADOUT[index]
	var packed := Weapon.model_scene(def.id)
	if packed == null:
		g.model = null
		return
	var model := packed.instantiate() as Node3D
	Weapon.no_shadows(model)
	Weapon.prepare_muzzle(model)
	var gun_root: Node3D = g.gun_root
	gun_root.add_child(model)
	var fit := Weapon.fit_model(model, def.id, k._rest)
	gun_root.position = fit.root
	(g.muzzle as Node3D).position = fit.muzzle
	g.model = model





static func free_ghosts(k: Killcam) -> void:
	for id in k._ghosts:
		var root: Node3D = k._ghosts[id].root
		if is_instance_valid(root):
			root.queue_free()
	k._ghosts.clear()
	for n in k._nades:
		if is_instance_valid(n):
			n.queue_free()
	k._nades.clear()
	for kn in k._knives:
		if is_instance_valid(kn):
			kn.queue_free()
	k._knives.clear()
	k._cam = null





static func apply_frames(k: Killcam, t: float) -> void:
	var frames: Array = k._clip.frames
	while k._frame_i < frames.size() - 2 and float(frames[k._frame_i + 1][0]) <= t:
		k._frame_i += 1
	var a: Array = frames[k._frame_i]
	var b: Array = frames[mini(k._frame_i + 1, frames.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var w := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	var pa: Dictionary = a[1]
	var pb: Dictionary = b[1]
	for id in k._ghosts:
		var sa: Variant = pa.get(id)
		var sb: Variant = pb.get(id)
		if sa == null and sb == null:
			(k._ghosts[id].root as Node3D).visible = false
			continue
		pose_ghost(k, k._ghosts[id], sa, sb, w, id == int(k._clip.info.get("k", 0)))
	var nades: PackedVector3Array = a[2] if w < 0.5 else b[2]
	var na: PackedVector3Array = a[2]
	var nb: PackedVector3Array = b[2]
	for i in k._nades.size():
		k._nades[i].visible = i < nades.size()
		if i < nades.size():
			var at := nades[i]
			# Glide between the two snapshots like the ghosts do, so the frag tumbles and streaks
			# smoothly instead of hopping (#342). Same count and close: the same grenade in both.
			if na.size() == nb.size() and na[i].distance_to(nb[i]) < 3.0:
				at = na[i].lerp(nb[i], w)
			k._nades[i].global_position = at
	var fk: Array = a if w < 0.5 else b
	var knives: Array = fk[3] if fk.size() > 3 else []
	for i in k._knives.size():
		k._knives[i].visible = i < knives.size()
		if i < knives.size():
			k._knives[i].global_transform = knives[i]





static func pose_ghost(k: Killcam, g: Dictionary, sa: Variant, sb: Variant, w: float, is_killer: bool) -> void:
	var s: Array = sa if sa != null else sb
	if sa != null and sb != null and w >= 0.5:
		s = sb
	var alive := bool(s[5])
	var root: Node3D = g.root
	# The killer's camera stays where they were if they die first (a grenade still in the air).
	root.visible = alive
	if not alive:
		return
	var pos: Vector3 = s[0]
	var yaw := float(s[1])
	var pitch := float(s[2])
	var crouch := float(s[3])
	var flip := float(s[7]) if s.size() > 7 else 0.0
	var thr := float(s[8]) if s.size() > 8 else 0.0
	var rel := float(s[9]) if s.size() > 9 else 0.0
	if sa != null and sb != null and bool(sa[5]) == bool(sb[5]):
		var a: Array = sa
		var b: Array = sb
		if (a[0] as Vector3).distance_to(b[0]) < Killcam.SNAP_JUMP:
			pos = (a[0] as Vector3).lerp(b[0], w)
			yaw = lerp_angle(float(a[1]), float(b[1]), w)
			pitch = lerpf(float(a[2]), float(b[2]), w)
			crouch = lerpf(float(a[3]), float(b[3]), w)
			if a.size() > 7 and b.size() > 7:
				# lerp_angle, not lerpf: the flip runs 0 -> -TAU in one move, and a plain lerp between a
				# sample near -TAU and the next one at 0 spun the body the long way back (#236).
				flip = lerp_angle(float(a[7]), float(b[7]), w)
			if a.size() > 8 and b.size() > 8:
				thr = lerpf(float(a[8]), float(b[8]), w)
			if a.size() > 9 and b.size() > 9:
				rel = lerpf(float(a[9]), float(b[9]), w)
	root.global_position = pos
	root.rotation = Vector3(0.0, yaw, 0.0)
	var head: Node3D = g.head
	head.position.y = lerpf(Player.STAND_EYE, Player.CROUCH_EYE, crouch)
	head.rotation.x = pitch
	if not is_killer:
		# #252: the recorded weapon index picks the reload style, so the ghost's left hand goes to the
		# mag instead of only tilting the torso.
		var kind: StringName = &"mag"
		var wi := int(s[4]) if s.size() > 4 else 0
		if wi >= 0 and wi < Weapon.LOADOUT.size():
			kind = Weapon.LOADOUT[wi].reload_style
		Player.pose_body(g.body, crouch, int(s[6]) if s.size() > 6 else Player.MOVE_NONE, flip, thr, rel, kind)
	ghost_weapon(k, g, int(s[4]))





static func tracer(k: Killcam, from: Vector3, to: Vector3, weapon_id: StringName, life: float) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var def := Game.weapon_def(weapon_id)
	var width := def.tracer_width if def else 0.02
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.65, 0.2) if weapon_id == &"shotgun" else Color(1.0, 0.82, 0.28)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 3.0
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	k.get_tree().current_scene.add_child(mesh_inst)
	mesh_inst.global_position = (from + to) * 0.5
	mesh_inst.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
	k.get_tree().create_timer(life).timeout.connect(mesh_inst.queue_free)


## Live pawns, grenades, and the HUD go away for the replay; _end_playback brings them back.



static func hide_live_world(k: Killcam) -> void:
	k._hidden.clear()
	hide_new_pawns(k)
	k._hud = k.get_tree().get_first_node_in_group("hud") as CanvasItem
	if k._hud:
		k._hud_was_visible = k._hud.visible
		k._hud.visible = false


## Also catches pawns that spawn during the replay (a join, a replacement bot).



static func hide_new_pawns(k: Killcam) -> void:
	for group in ["player", "grenade", "knife"]:
		for n in k.get_tree().get_nodes_in_group(group):
			var n3 := n as Node3D
			if n3 and n3.visible:
				n3.visible = false
				k._hidden.append(n3)


## #317 stap 2: de 2D-laag (balken, titel, crosshair, VHS) zit in KillcamOverlay.
