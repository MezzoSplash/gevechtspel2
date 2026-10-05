class_name PlayerClasses
extends RefCounted
## Classes (custom loadouts): data model, validation, and the local save file.
## A class is {name, primary, secondary, grenades}; `grenades` is per-type counts, total <= MAX_GRENADES.
## The grenade slot holds MAX_GRENADES throwables in any mix: frag grenades (G) and throwing knives (F).
## The wire loadout is the same dict without the name. The server checks it with `parse_loadout`.

const PRIMARIES: Array[StringName] = [&"rifle", &"shotgun", &"sniper", &"smg"]
## The revolver is a sidearm option next to the pistol: slow and heavy-hitting against fast and forgiving.
const SECONDARIES: Array[StringName] = [&"pistol", &"revolver"]
const GRENADE_TYPES: Array[StringName] = [&"frag", &"knife"]
const GRENADE_NAMES := {&"frag": "Frag", &"knife": "Knife"}
## Class editor rows: what the item is and which key throws it.
const GRENADE_LABELS := {&"frag": "Frag grenades  [G]", &"knife": "Throwing knives  [F]"}
const MAX_GRENADES := 3
const MAX_CLASSES := 8
const NAME_MAX := 16
const SAVE_PATH := "user://classes.cfg"

const DEFAULTS := [
	{"name": "Rifleman", "primary": "rifle", "secondary": "pistol", "grenades": {"frag": 2}},
	{"name": "Breacher", "primary": "shotgun", "secondary": "pistol", "grenades": {"frag": 3}},
	{"name": "Sniper", "primary": "sniper", "secondary": "pistol", "grenades": {"frag": 1}},
	{"name": "Runner", "primary": "smg", "secondary": "revolver", "grenades": {"frag": 1, "knife": 2}},
]


## What a human gets until the server has their pick (same as the old fixed loadout's grenade count).
static func default_loadout() -> Dictionary:
	return to_loadout(DEFAULTS[0])


static func weapon_label(id: StringName) -> String:
	var def := Game.weapon_def(id)
	return def.display_name if def else String(id).capitalize()


## "Rifle · Pistol · 2 Frag" for lists and the HUD.
static func summary(c: Dictionary) -> String:
	var parts: PackedStringArray = [weapon_label(StringName(c.primary)), weapon_label(StringName(c.secondary))]
	var g: Dictionary = c.grenades
	for t in GRENADE_TYPES:
		var n := int(g.get(String(t), 0))
		if n > 0:
			var item: String = GRENADE_NAMES.get(t, String(t).capitalize())
			if n > 1 and t == &"knife":
				item = "Knives"
			parts.append("%d %s" % [n, item])
	if grenade_total(g) == 0:
		parts.append("no grenades")
	return " · ".join(parts)


static func grenade_total(g: Dictionary) -> int:
	var total := 0
	for k in g:
		total += maxi(int(g[k]), 0)
	return total


## One line, no control characters, capped. Empty falls back so a class never has a blank name.
static func clean_class_name(n: String, fallback: String = "Class") -> String:
	var out := ""
	var last_space := true
	for ch in n:
		var code := ch.unicode_at(0)
		if code < 32 or code == 127 or (code >= 0x80 and code < 0xA0):
			ch = " "
		if ch == " " or ch == "\t":
			if last_space:
				continue
			out += " "
			last_space = true
		else:
			out += ch
			last_space = false
	out = out.strip_edges().substr(0, NAME_MAX).strip_edges()
	return out if out != "" else fallback


## Local file: fix what can be fixed (unknown gun → first option, too many grenades → trimmed).
static func sanitize_class(raw: Variant, fallback_name: String = "Class") -> Dictionary:
	var d: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var primary := StringName(str(d.get("primary", "")))
	if not PRIMARIES.has(primary):
		primary = PRIMARIES[0]
	var secondary := StringName(str(d.get("secondary", "")))
	if not SECONDARIES.has(secondary):
		secondary = SECONDARIES[0]
	var g_in: Variant = d.get("grenades", {})
	var g: Dictionary = {}
	var left := MAX_GRENADES
	for t in GRENADE_TYPES:
		var n := 0
		if typeof(g_in) == TYPE_DICTIONARY:
			n = clampi(int((g_in as Dictionary).get(String(t), 0)), 0, left)
		g[String(t)] = n
		left -= n
	return {
		"name": clean_class_name(str(d.get("name", "")), fallback_name),
		"primary": String(primary),
		"secondary": String(secondary),
		"grenades": g,
	}


static func to_loadout(c: Dictionary) -> Dictionary:
	return {"primary": str(c.primary), "secondary": str(c.secondary), "grenades": (c.grenades as Dictionary).duplicate()}


## Server side: strict. Anything off (unknown gun or grenade type, negative, total > 3) → {} (rejected).
static func parse_loadout(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = raw
	if typeof(d.get("primary")) != TYPE_STRING or typeof(d.get("secondary")) != TYPE_STRING:
		return {}
	var primary := StringName(d.primary)
	var secondary := StringName(d.secondary)
	if not PRIMARIES.has(primary) or not SECONDARIES.has(secondary):
		return {}
	if typeof(d.get("grenades")) != TYPE_DICTIONARY:
		return {}
	var g_in: Dictionary = d.grenades
	var g: Dictionary = {}
	var total := 0
	for k in g_in:
		if typeof(k) != TYPE_STRING or not GRENADE_TYPES.has(StringName(k)) or typeof(g_in[k]) != TYPE_INT:
			return {}
		var n: int = g_in[k]
		if n < 0 or n > MAX_GRENADES:
			return {}
		g[k] = n
		total += n
	if total > MAX_GRENADES:
		return {}
	for t in GRENADE_TYPES:
		if not g.has(String(t)):
			g[String(t)] = 0
	return {"primary": String(primary), "secondary": String(secondary), "grenades": g}


static func defaults() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in DEFAULTS:
		out.append(sanitize_class(c))
	return out


## Returns {classes, last}. A missing or empty file gives the defaults.
static func load_file(path: String = SAVE_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var classes: Array[Dictionary] = []
	var last := 0
	if cfg.load(path) == OK:
		last = int(cfg.get_value("meta", "last", 0))
		var n := clampi(int(cfg.get_value("meta", "count", 0)), 0, MAX_CLASSES)
		for i in n:
			var sec := "class_%d" % i
			if not cfg.has_section(sec):
				continue
			classes.append(sanitize_class({
				"name": cfg.get_value(sec, "name", ""),
				"primary": cfg.get_value(sec, "primary", ""),
				"secondary": cfg.get_value(sec, "secondary", ""),
				"grenades": cfg.get_value(sec, "grenades", {}),
			}, "Class %d" % (i + 1)))
	if classes.is_empty():
		classes = defaults()
		last = 0
	return {"classes": classes, "last": clampi(last, 0, classes.size() - 1)}


static func save_file(classes: Array[Dictionary], last: int, path: String = SAVE_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "count", mini(classes.size(), MAX_CLASSES))
	cfg.set_value("meta", "last", clampi(last, 0, maxi(classes.size() - 1, 0)))
	for i in mini(classes.size(), MAX_CLASSES):
		var c := classes[i]
		var sec := "class_%d" % i
		cfg.set_value(sec, "name", c.name)
		cfg.set_value(sec, "primary", c.primary)
		cfg.set_value(sec, "secondary", c.secondary)
		cfg.set_value(sec, "grenades", c.grenades)
	return cfg.save(path)
