class_name WeaponKit
extends RefCounted
## Where a gun's art lives: one folder per weapon id, found by its name, so an artist adds or replaces
## a gun by dropping files in and no code changes (docs/art/wapens.md is the artist's side of this).
##
##   assets/weapons/<id>/<id>.tscn    the gun scene (or <id>.glb when there is nothing but the model)
##   assets/weapons/<id>/fire*.ogg    one or more shots; with several, every shot picks one
##   assets/weapons/<id>/reload.ogg   the reload, stretched to the gun's reload time
##   assets/weapons/<id>/draw.ogg     pulling the gun out
##   assets/weapons/<id>/dry.ogg      the trigger on an empty mag
##
## Sounds may be .ogg, .wav or .mp3. Anything else in the folder (textures, meshes, VFX scenes,
## animation libraries) belongs to the scene and is left alone. A folder whose name starts with "_" is
## not a gun (the template). Guns without a folder still use the flat files from before the kits
## (assets/weapons/<id>.glb / .tscn) and WeaponDef.fire_sound, so nothing has to move at once.
## Everything is loaded once and kept: the old preloaded table did the same for the scenes.

const ROOT := "res://assets/weapons"
## Ids that hold another kit's model: the shank is the throwing knife held as a primary.
const SHARED := {&"shank": &"knife"}
const SOUND_EXTS: Array[String] = ["ogg", "wav", "mp3"]
## File-name start -> sound slot. The first match wins, so "fire_2.ogg" is a fire sound.
const SOUND_SLOTS := [["fire", &"fire"], ["shot", &"fire"], ["reload", &"reload"], ["draw", &"draw"],
	["equip", &"draw"], ["dry", &"dry"], ["empty", &"dry"], ["distant", &"distant"]]

static var _scenes: Dictionary = {} # kit id -> PackedScene (null when there is none)
static var _sounds: Dictionary = {} # kit id -> {fire: Array[AudioStream], reload, draw, dry}


## The kit a weapon id draws from (itself, or the one in SHARED).
static func kit_id(id: StringName) -> StringName:
	return SHARED.get(id, id)


static func folder(id: StringName) -> String:
	return "%s/%s" % [ROOT, kit_id(id)]


## True when this weapon has its own folder (a kit), not only the flat files from before.
static func has_folder(id: StringName) -> bool:
	return DirAccess.dir_exists_absolute(folder(id))


## The scene file for a weapon, in the order the game looks: the kit's scene, the kit's bare model,
## then the flat files from before the kits. "" when there is no model at all.
static func scene_path(id: StringName) -> String:
	var k := String(kit_id(id))
	for p in ["%s/%s.tscn" % [folder(id), k], "%s/%s.glb" % [folder(id), k],
			"%s/%s.tscn" % [ROOT, k], "%s/%s.glb" % [ROOT, k]]:
		if ResourceLoader.exists(p):
			return p
	return ""


## The gun scene to instance for `id`, loaded once. Null when the weapon has no model.
static func scene(id: StringName) -> PackedScene:
	var k := kit_id(id)
	if not _scenes.has(k):
		var p := scene_path(id)
		_scenes[k] = load(p) as PackedScene if p != "" else null
	return _scenes[k]


## The kit's sounds by slot: "fire" is a list (variations), the rest one stream or null.
static func sounds(id: StringName) -> Dictionary:
	var k := kit_id(id)
	if not _sounds.has(k):
		_sounds[k] = read_sounds(folder(id))
	return _sounds[k]


## Reads a folder's sound files into slots. Static and uncached, so the check can point it anywhere.
static func read_sounds(dir: String) -> Dictionary:
	var out := {&"fire": [] as Array[AudioStream], &"reload": null, &"draw": null, &"dry": null, &"distant": null}
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(ResourceLoader.list_directory(dir))
	files.sort() # fire.ogg, fire_2.ogg, ... in a stable order
	for f in files:
		var file := String(f)
		if file.ends_with("/") or not (file.get_extension().to_lower() in SOUND_EXTS):
			continue
		var slot := sound_slot(file)
		if slot == &"":
			continue
		var stream := load("%s/%s" % [dir, file]) as AudioStream
		if stream == null:
			continue
		if slot == &"fire":
			(out[&"fire"] as Array).append(stream)
		elif out[slot] == null:
			out[slot] = stream
	return out


## Which slot a sound file is for, from the start of its name; &"" when it is none of them.
static func sound_slot(file: String) -> StringName:
	var base := file.get_file().get_basename().to_lower()
	for pair in SOUND_SLOTS:
		if base.begins_with(String(pair[0])):
			return pair[1]
	return &""


## One shot's sound: a random one of the kit's fire sounds, else the WeaponDef's own.
static func fire_sound(def: WeaponDef) -> AudioStream:
	if def == null:
		return null
	var list: Array = sounds(def.id)[&"fire"]
	if not list.is_empty():
		return list[randi() % list.size()]
	return def.fire_sound


## The kit's far layer (#370): the same shot lowpassed with a tail, so a fight at 40 m still has body.
## Named `distant.wav` on purpose: any name starting with "fire" would be picked as a close variant.
static func distant_sound(id: StringName) -> AudioStream:
	return sounds(id).get(&"distant")


## The kit's reload / draw / dry sound, or `fallback` when the kit has none.
static func sound(id: StringName, slot: StringName, fallback: AudioStream = null) -> AudioStream:
	var s: AudioStream = sounds(id).get(slot)
	return s if s != null else fallback


## Every kit folder that is a gun (not "_template"), for the check and the weapon lab.
static func folders() -> Array[StringName]:
	var out: Array[StringName] = []
	for f in ResourceLoader.list_directory(ROOT):
		var name := String(f)
		if name.ends_with("/") and not name.begins_with("_"):
			out.append(StringName(name.trim_suffix("/")))
	return out


## What is wrong with a kit folder, in the artist's words (Dutch, like docs/art/wapens.md): the check
## fails on any of these and the weapon lab shows them. Empty means the kit is fine.
static func problems(id: StringName) -> Array[String]:
	var out: Array[String] = []
	var dir := "%s/%s" % [ROOT, id]
	var known := id == &"knife"
	for d in Weapon.LOADOUT:
		known = known or (d as WeaponDef).id == id
	if not known:
		out.append("map '%s' hoort bij geen wapen: de mapnaam moet een wapen-id zijn (%s)" % [id, ", ".join(ids_known())])
		return out
	for f in ResourceLoader.list_directory(dir):
		var file := String(f)
		if file.get_extension().to_lower() in SOUND_EXTS and sound_slot(file) == &"":
			out.append("geluid '%s' heeft geen bekende naam: begin met fire, reload, draw of dry" % file)
	var path := ""
	for p in ["%s/%s.tscn" % [dir, id], "%s/%s.glb" % [dir, id]]:
		if ResourceLoader.exists(p):
			path = p
			break
	if path == "":
		return out # a folder with only sounds is fine: the model stays the old one
	var ps := load(path) as PackedScene
	var root := ps.instantiate() if ps else null
	if not (root is Node3D):
		out.append("'%s' laadt niet als 3D-scene" % path.get_file())
		if root:
			root.free()
		return out
	var model := root as Node3D
	var muzzle := WeaponModel.muzzle_node(model)
	var box := WeaponModel.aabb_in_parent(model, muzzle)
	if box.size.x < 0.05:
		out.append("'%s' heeft geen zichtbaar model" % path.get_file())
	elif box.size.x < maxf(box.size.y, box.size.z):
		out.append("het model ligt niet langs X: de loop moet langs +X lopen, de monding aan de +X kant")
	if muzzle == null:
		if not is_blade(id):
			out.append("geen Muzzle: zet een Marker3D met de naam Muzzle op het eind van de loop")
	elif box.size.x >= 0.05:
		var mx := WeaponModel.origin_in_parent(model, muzzle).x
		if mx < box.get_center().x:
			out.append("Muzzle staat aan de achterkant: hij hoort op het eind van de loop, aan de +X kant")
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for name in anim.get_animation_list():
			var bare := String(name).get_slice("/", String(name).get_slice_count("/") - 1)
			var ok := bare == "RESET" # Godot's own rest pose track
			for kind in WeaponModel.CLIP_KINDS:
				ok = ok or bare == String(kind) or bare.ends_with("_" + String(kind))
			if not ok:
				out.append("animatie '%s' wordt niet gebruikt: noem hem fire, reload of draw" % name)
	model.free()
	return out


## A kit for a blade (the knife, and the shank that holds it) has no barrel, so no Muzzle either.
static func is_blade(id: StringName) -> bool:
	if kit_id(id) == &"knife":
		return true
	for d in Weapon.LOADOUT:
		if (d as WeaponDef).id == id:
			return (d as WeaponDef).melee
	return false


## Every weapon id a kit folder can be named after.
static func ids_known() -> Array[String]:
	var out: Array[String] = []
	for d in Weapon.LOADOUT:
		out.append(String((d as WeaponDef).id))
	out.append("knife")
	return out


## Loads every gun's scene and sounds now (and the knife's), so the first spawn does not.
static func warm(defs: Array) -> void:
	for d in defs:
		scene((d as WeaponDef).id)
		sounds((d as WeaponDef).id)
	scene(&"knife")


## Forget what was loaded, so the weapon lab picks up files an artist just changed: the kit's scenes
## are read again from disk, not from Godot's own resource cache.
static func clear_cache() -> void:
	_scenes.clear()
	_sounds.clear()


## Reloads one gun's scene from disk (the weapon lab's L key), past Godot's resource cache.
static func reload_scene(id: StringName) -> PackedScene:
	var p := scene_path(id)
	var ps: PackedScene = null
	if p != "":
		ps = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as PackedScene
	_scenes[kit_id(id)] = ps
	_sounds.erase(kit_id(id))
	return ps
