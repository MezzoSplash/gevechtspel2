class_name BotRoutes
extends RefCounted
## #270: hand-authored movement routes, so a bot takes a wallrun or a slide on purpose instead of
## stumbling into one. A route is a short polyline with a kind; it lives in
## `data/bot_routes/<map>.json` and is plain data - no navmesh, no per-map code.
##
## Validation happens once per map, on the first look-up: every segment of a route is traced through
## the world and every point has to have floor under it, so a route that runs through a wall (a map
## change, a typo in a hand-written file) is dropped with a warning instead of steering a bot into a
## wall for the rest of the match.
##
## Format, one file per map:
##   {"routes": [
##     {"kind": "wallrun", "points": [[x, y, z], [x, y, z], ...]},
##     {"kind": "slide",   "points": [...]},
##     {"kind": "surf",    "points": [...]}
##   ]}

## Data, not tooling: `export_presets.cfg` excludes `tools/*`, so routes that live there would be
## missing from every exported build (the dedicated server included).
const DIR := "res://data/bot_routes/"
const KINDS: Array[StringName] = [&"wallrun", &"slide", &"surf"]
## A route is picked up when its first point is this close to the bot, and it has to lead towards
## the goal, or a bot that walks past the start of a route would turn around for it.
const REACH := 3.0
const WORLD_MASK := 1 # arena only; pawns are layer 2
const FLOOR_DROP := 3.0 # m: a route point without floor this far below it is not walkable
const WALKABLE_NY := 0.7 # cos 45°, same as the navmesh's agent_max_slope

static var _cache := {} # map id -> Array of routes (validated)
## #311/#360: een match kan zijn eerste bot-tik doen voordat de collision van de map er is (CSG wordt
## gebakken). Dan raakt elke straal niets en zouden alle routes voor de hele match weg zijn. Zo'n lege
## uitslag wordt daarom niet gecached: de volgende tik probeert het opnieuw.
## map id -> physics frame van de eerste poging die niets vond. Het venster telt in frames, niet in
## aanroepen: elke bot vraagt de routes per tik op, dus met 12 bots zou "120 aanroepen" maar ~10 ticks zijn
## en dan hing de wachttijd aan het aantal bots (review Chief, #400).
static var _retry := {}
static var _retry_warned := {}
const RETRY_SECONDS := 2.0 # ruim voor elke CSG-/navmesh-bake, en daarna geloven we de uitslag


## Every valid route on `map_id`. Empty when the map has no file; a broken file gives an empty list
## and one warning, not a crash per tick.
##
## #311/#360: the first bot tick of a match can come before the map's collision exists (CSG is baked
## after the scene is added), and then every route fails the floor test. That answer must not be cached,
## or the bots lose all their routes for the whole match. So an empty result from a file with routes is
## retried for a while (the world is there within a frame or two) and only then taken for the truth.
static func for_map(space: PhysicsDirectSpaceState3D, map_id: StringName) -> Array:
	if _cache.has(map_id):
		return _cache[map_id]
	var path := DIR + str(map_id) + ".json"
	if not FileAccess.file_exists(path):
		_cache[map_id] = []
		return []
	var raw := _read(path)
	var res := _validate_full(space, raw, path, false)
	var out: Array = res["routes"]
	if not raw.is_empty() and out.is_empty():
		var frame := Engine.get_physics_frames()
		var since := int(_retry.get(map_id, frame))
		if not _retry.has(map_id):
			_retry[map_id] = frame
		if frame - since < int(RETRY_SECONDS * Engine.physics_ticks_per_second):
			if not _retry_warned.has(map_id):
				_retry_warned[map_id] = true
				push_warning("BotRoutes: %s: no route passed yet (%d rays hit the world); the map is probably not loaded yet. The answer is not cached and the next tick tries again (#311/#360)" % [path, int(res["hits"])])
			return []
		# Uit de tijd: valideer nog een keer met de per-route-redenen, zodat een echt kapot bestand zich
		# alsnog meldt, en neem die uitslag dan over.
		res = _validate_full(space, raw, path, true)
		out = res["routes"]
	_cache[map_id] = out
	return out


## Drop every cached answer. For checks that load more than one map in one process (a real match loads
## one map and keeps its routes).
static func reset_cache() -> void:
	_cache.clear()
	_retry.clear()
	_retry_warned.clear()


## Routes from an explicit path (the check writes its own fixture). Not cached: a check may write a
## different file under the same name.
static func from_file(space: PhysicsDirectSpaceState3D, path: String) -> Array:
	return _validate(space, _read(path), path)


## The route worth taking now: its start is within REACH and its end is closer to `goal` than the bot
## is. The longest such route wins (a slide chain beats a single step).
static func pick(space: PhysicsDirectSpaceState3D, routes: Array, pos: Vector3, goal: Vector3) -> Dictionary:
	var here := flat_dist(pos, goal)
	var best := {}
	var best_len := 0.0
	for r in routes:
		var pts: Array = r["points"]
		if pts.is_empty():
			continue
		var start: Vector3 = pts[0]
		if Vector2(start.x - pos.x, start.z - pos.z).length() > REACH:
			continue
		var end: Vector3 = pts[pts.size() - 1]
		if flat_dist(end, goal) > here - 4.0:
			continue # it does not bring us nearer: walking there normally is fine
		var len := 0.0
		for i in range(1, pts.size()):
			len += (pts[i] as Vector3).distance_to(pts[i - 1] as Vector3)
		if len > best_len:
			best_len = len
			best = r
	return best


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _read(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("BotRoutes: %s is empty or unreadable" % path)
		return []
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("routes"):
		push_warning("BotRoutes: %s has no \"routes\" array" % path)
		return []
	var raw = (parsed as Dictionary)["routes"]
	return raw if typeof(raw) == TYPE_ARRAY else []


## Points as Vector3 and the one-time geometry test. Anything that fails is dropped, with the reason
## in the warning, so a hand-edited file is fixable from the log.
static func _validate(space: PhysicsDirectSpaceState3D, raw: Array, path: String) -> Array:
	var res := _validate_full(space, raw, path, true)
	var out: Array = res["routes"]
	return out


## The validator, plus how many rays hit any world geometry at all: zero hits means the world was not
## there yet, which for_map uses to decide that the answer must not be cached (#311/#360).
static func _validate_full(space: PhysicsDirectSpaceState3D, raw: Array, path: String, warn: bool) -> Dictionary:
	var out: Array = []
	var hits := 0
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d := entry as Dictionary
		var kind := StringName(str(d.get("kind", "")))
		if not KINDS.has(kind):
			_warn(warn, "BotRoutes: %s: unknown kind \"%s\"" % [path, kind])
			continue
		var pts: Array[Vector3] = []
		for p in (d.get("points", []) as Array):
			if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
				pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		if pts.size() < 2:
			_warn(warn, "BotRoutes: %s: a %s route needs two points" % [path, kind])
			continue
		var ok := true
		for i in range(1, pts.size()):
			var q := PhysicsRayQueryParameters3D.create(pts[i - 1] + Vector3.UP * 0.9, pts[i] + Vector3.UP * 0.9)
			q.collision_mask = WORLD_MASK
			var seg := space.intersect_ray(q)
			if not seg.is_empty():
				hits += 1
				_warn(warn, "BotRoutes: %s: %s route crosses world between point %d and %d" % [path, kind, i - 1, i])
				ok = false
				break
		if not ok:
			continue
		for p in pts:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p + Vector3.DOWN * FLOOR_DROP)
			q.collision_mask = WORLD_MASK
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				hits += 1
			if hit.is_empty() or (hit.normal as Vector3).y < WALKABLE_NY:
				_warn(warn, "BotRoutes: %s: %s route has no walkable floor at %s" % [path, kind, p])
				ok = false
				break
		if ok:
			out.append({"kind": kind, "points": pts})
	return {"routes": out, "hits": hits}


## A warning that the first, too-early validation can stay quiet about: otherwise a map that is not
## loaded yet costs 60 lines before the one line that says why.
static func _warn(on: bool, msg: String) -> void:
	if on:
		push_warning(msg)
