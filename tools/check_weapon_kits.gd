extends Node3D
## Weapon kits (docs/art/wapens.md): every gun's art is found from its folder, every kit folder in the
## repo is valid (named after a weapon, model along +X, a Muzzle at the barrel's end, known clip and
## sound names), and what a gun scene may hold does what the guide promises: everything under Muzzle
## is the flash (particles burst, meshes and lights show for flash_time), the flash is no part of the
## gun's size, clips are found by name and a reload clip is stretched to the reload time.
##   godot --headless res://tools/check_weapon_kits.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	# 1) Every gun in the armory finds a model and a fire sound; the shank holds the knife's.
	for d in Weapon.LOADOUT:
		var def := d as WeaponDef
		_ok(WeaponKit.scene(def.id) != null, "%s has a model (%s)" % [def.id, WeaponKit.scene_path(def.id)])
		_ok(WeaponKit.fire_sound(def) != null, "%s has a fire sound" % def.id)
	_ok(WeaponKit.scene(&"knife") != null, "the knife has a model")
	_ok(WeaponKit.scene_path(&"shank") == WeaponKit.scene_path(&"knife"), "the shank holds the knife kit")
	_ok(WeaponKit.scene_path(&"smg") == "res://assets/weapons/smg/smg.tscn", "the SMG is a kit folder")
	var smg: WeaponDef = Weapon.LOADOUT[4]
	_ok(WeaponKit.fire_sound(smg) == smg.fire_sound, "no kit sound: the WeaponDef's own fire sound")

	# 2) Every kit folder in the repo passes the artist's rules.
	var folders := WeaponKit.folders()
	_ok(folders.has(&"smg"), "kit folders found: %s" % ", ".join(folders))
	for id in folders:
		var issues := WeaponKit.problems(id)
		_ok(issues.is_empty(), "kit '%s' is valid%s" % [id, "" if issues.is_empty() else ": " + "; ".join(issues)])
	_ok(not folders.has(&"_template"), "the template is not a gun")
	_ok(WeaponKit.problems(&"_template").size() == 1, "a folder not named after a weapon is reported")

	# 3) Sound names.
	var names := {"fire.ogg": &"fire", "fire_2.wav": &"fire", "Shot-B.ogg": &"fire", "reload.wav": &"reload",
		"Reload_full.ogg": &"reload", "draw.ogg": &"draw", "equip.wav": &"draw", "dry.ogg": &"dry",
		"empty.wav": &"dry", "click.ogg": &""}
	var named := true
	for f in names:
		named = named and WeaponKit.sound_slot(f) == names[f]
	_ok(named, "sound files land in their slot by the start of their name")

	# 4) Clip names: bare, in a library, or ending in _kind (the SMG's).
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for n in ["fire", "reload", "idle"]:
		var a := Animation.new()
		a.length = 0.5
		lib.add_animation(n, a)
	anim.add_animation_library(&"guns", lib)
	var lib2 := AnimationLibrary.new()
	var a2 := Animation.new()
	a2.length = 1.0
	lib2.add_animation(&"weapon_x_draw", a2)
	anim.add_animation_library(&"", lib2)
	_ok(WeaponModel.clip(anim, &"fire") == &"guns/fire", "fire clip in a library")
	_ok(WeaponModel.clip(anim, &"reload") == &"guns/reload", "reload clip in a library")
	_ok(WeaponModel.clip(anim, &"draw") == &"weapon_x_draw", "a clip ending in _draw counts")
	anim.free()

	# 5) A gun scene as the guide describes it, built here: the flash under Muzzle.
	var gun := _test_gun()
	add_child(gun)
	WeaponModel.prepare_muzzle(gun)
	var flash_mesh := gun.get_node("Muzzle/FlashMesh") as MeshInstance3D
	var flash_light := gun.get_node("Muzzle/FlashLight") as OmniLight3D
	var sparks := gun.get_node("Muzzle/Sparks") as GPUParticles3D
	_ok(not flash_mesh.visible and not flash_light.visible and not sparks.emitting, "prepared: the flash is off")
	_ok(WeaponModel.has_own_light(gun), "a light under Muzzle is the gun's own")
	var fit := WeaponModel.fit_model(gun, &"rifle", Vector3(0.2, -0.2, -0.4))
	_ok((fit.muzzle as Vector3).distance_to(WeaponModel.origin_in_parent(gun, gun.get_node("Muzzle"))) < 0.001, "tracers leave from Muzzle")
	var box := WeaponModel.aabb_in_parent(gun, gun.get_node("Muzzle"))
	_ok(is_equal_approx(box.size.z, 0.42), "the flash is no part of the gun's size (%.3f m long)" % box.size.z)
	_ok(fit.has("sight_y"), "a Sight marker sets the aiming height")
	var drew := WeaponModel.play_model_shot(gun, 1.0, 10.0, 0.05)
	var gun_anim := gun.get_node("AnimationPlayer") as AnimationPlayer
	_ok(drew and flash_mesh.visible and flash_light.visible and sparks.emitting, "a shot shows the flash and bursts the particles")
	_ok(gun_anim.is_playing() and gun_anim.current_animation == &"fire", "a shot plays the fire clip")
	await get_tree().create_timer(0.15).timeout
	# A long first frame can fire this timer before the tween's own step in the same frame.
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(not flash_mesh.visible and not flash_light.visible, "the flash goes off after flash_time")
	_ok(WeaponModel.play_clip(gun, &"reload", 2.0) and is_equal_approx(gun_anim.speed_scale, 0.4), "a 0.8 s reload clip is stretched to a 2 s reload")
	WeaponModel.stop_clip(gun, &"reload")
	_ok(not gun_anim.is_playing(), "a cut reload stops its clip")
	_ok(not WeaponModel.play_clip(gun, &"draw"), "no draw clip: nothing plays")

	# 6) Old scenes keep working: a mesh named Muzzle (the low-poly barrel tips) is not the point,
	# the older "muzzle_flash" name still is, and a blade needs no Muzzle at all.
	var tip_gun := Node3D.new()
	var tip := MeshInstance3D.new()
	tip.name = "Muzzle"
	tip.mesh = BoxMesh.new()
	tip_gun.add_child(tip)
	_ok(WeaponModel.muzzle_node(tip_gun) == null, "a barrel-tip mesh named Muzzle is not taken for the muzzle point")
	var old_name := Node3D.new()
	old_name.name = "muzzle_flash"
	tip_gun.add_child(old_name)
	_ok(WeaponModel.muzzle_node(tip_gun) == old_name, "the older name muzzle_flash still marks the muzzle")
	tip_gun.free()
	_ok(WeaponKit.is_blade(&"knife") and WeaponKit.is_blade(&"shank") and not WeaponKit.is_blade(&"rifle"), "the knife and the shank are blades, they need no Muzzle")
	_ok(WeaponKit.problems(&"knife").is_empty(), "the knife kit (or its old file) has nothing to report")

	# 7) In a real pawn's weapon: a gun with its own reload clip moves itself, the code's own reload
	# motion and loose parts stay out; a gun without one keeps the code's motion.
	var pawn := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	pawn.set_physics_process(false)
	add_child(pawn)
	var w := pawn.weapon
	var kit_gun := _test_gun()
	kit_gun.visible = false
	WeaponModel.prepare_muzzle(kit_gun)
	w.add_child(kit_gun)
	(w._view_models[&"rifle"] as Node).queue_free()
	w._view_models[&"rifle"] = kit_gun
	w._equip_def(Weapon.LOADOUT[0], false)
	w.ammo = 1
	w._start_reload()
	w._apply_reload_pose(0.3)
	var kit_anim := kit_gun.get_node("AnimationPlayer") as AnimationPlayer
	_ok(w._own_reload() and kit_anim.current_animation == &"reload", "a kit reload clip plays on R")
	_ok(w._reload_rot == Vector3.ZERO and w._reload_dip == Vector3.ZERO and not w._reload_mag.visible, "with its own clip the code's reload tilt and mag stay out")
	_ok(w._own_light(), "a kit flash light replaces the shared one")
	w._cancel_reload()
	_ok(not kit_anim.is_playing(), "a cancelled reload stops the clip")
	w._equip_def(Weapon.LOADOUT[1], false) # the pistol: an old model without clips
	w.ammo = 1
	w._start_reload()
	w._apply_reload_pose(0.3)
	_ok(w._reload_rot != Vector3.ZERO, "a gun without a clip keeps the code's reload motion")
	_ok(not w._own_light(), "an old gun keeps the shared muzzle light")
	pawn.queue_free()

	print("WEAPON KITS CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


## A 0.42 m gun along +X with a flash mesh, light and particles under Muzzle, a Sight and two clips.
func _test_gun() -> Node3D:
	var gun := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.42, 0.08, 0.04)
	body.mesh = box
	gun.add_child(body)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.21, 0.01, 0.0)
	gun.add_child(muzzle)
	var flash := MeshInstance3D.new()
	flash.name = "FlashMesh"
	var big := QuadMesh.new()
	big.size = Vector2(1.0, 1.0) # bigger than the gun: must not count for its size
	flash.mesh = big
	flash.position.x = 0.5
	muzzle.add_child(flash)
	var light := OmniLight3D.new()
	light.name = "FlashLight"
	muzzle.add_child(light)
	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	muzzle.add_child(sparks)
	var sight := Marker3D.new()
	sight.name = "Sight"
	sight.position = Vector3(0.15, 0.05, 0.0)
	gun.add_child(sight)
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	var lib := AnimationLibrary.new()
	for n in [["fire", 0.1], ["reload", 0.8]]:
		var a := Animation.new()
		a.length = n[1]
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(n[0], a)
	anim.add_animation_library(&"", lib)
	gun.add_child(anim)
	return gun
