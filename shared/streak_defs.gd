class_name StreakDefs
extends RefCounted
## Killstreak catalog (#387): the streaks a player can pick, what each costs in kills, its name and
## blurb, and whether a bot may use it. The menu lists this table, the server validates a pick
## against it, and Streaks awards and fires the chosen ones. Overdrive (#388) joins the table when
## that streak exists; until then it is not listed, so the menu never offers a streak that does not work.
## A charge stays a bit in Game.streak_charges keyed by id, so an unchanged pick earns and fires
## exactly what it did before (#387: replay unchanged).

const MAX_SLOTS := 3

const CATALOG: Array[Dictionary] = [
	{"id": &"uav", "kills": 3, "name": "UAV",
		"blurb": "25 s radar: your team sees the enemy on the minimap.", "bots": true},
	{"id": &"rcxd", "kills": 5, "name": "RCXplodie",
		"blurb": "Drive a remote car and blow it up next to the enemy.", "bots": true},
	{"id": &"los", "kills": 7, "name": "LOS",
		"blurb": "Your hands leave the body and fight on their own.", "bots": false},
]


static func def(id: StringName) -> Dictionary:
	for d in CATALOG:
		if StringName(d["id"]) == id:
			return d
	return {}


static func has(id: StringName) -> bool:
	return not def(id).is_empty()


static func kills(id: StringName) -> int:
	return int(def(id).get("kills", 0))


static func name_of(id: StringName) -> String:
	return str(def(id).get("name", String(id)))


static func blurb(id: StringName) -> String:
	return str(def(id).get("blurb", ""))


static func bots_allowed(id: StringName) -> bool:
	return bool(def(id).get("bots", false))


## The charge bit for a streak id. One bit per id, so the old three keep their bits and a replay of
## an unchanged pick stays identical.
static func bit(id: StringName) -> int:
	match id:
		&"uav":
			return GameState.CHARGE_RADAR
		&"rcxd":
			return GameState.CHARGE_RCXD
		&"los":
			return GameState.CHARGE_LOS
	return 0


## The default pick: UAV, RCXplodie, LOS. An untouched settings file earns exactly what it used to.
static func default_ids() -> Array:
	return [&"uav", &"rcxd", &"los"]


## A bot's pick: the default without the streaks a bot may not use.
static func bot_ids() -> Array:
	var out: Array = []
	for d in CATALOG:
		if bool(d["bots"]):
			out.append(StringName(d["id"]))
	return out


## True when two ids in the list cost the same kills: both would bank on the same kill, so only one
## may be picked. Unknown ids are ignored.
static func cost_conflict(ids: Array) -> bool:
	var seen := {}
	for raw in ids:
		var k := kills(StringName(raw))
		if k <= 0:
			continue
		if seen.has(k):
			return true
		seen[k] = true
	return false


## Validates a pick: known ids only, no duplicates, at most MAX_SLOTS, and no two streaks with the
## same kill cost. Sorted by kill cost. An invalid pick becomes the default, so a stale or forged
## settings file never leaves a player without streaks. The menu warns about a shared cost first.
static func sanitize(raw: Variant) -> Array:
	var ids: Array = []
	var list: Array = []
	if raw is Array:
		list = raw
	elif raw is PackedStringArray:
		list = Array(raw) # settings.cfg stores the pick as a PackedStringArray
	for e in list:
		var id := StringName(str(e))
		if not has(id) or ids.has(id):
			continue
		ids.append(id)
	if ids.is_empty() or ids.size() > MAX_SLOTS or cost_conflict(ids):
		return default_ids()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return kills(a) < kills(b))
	return ids
