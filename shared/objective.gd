class_name Objective
extends RefCounted
## A carryable world objective: CTF flags now, the Defuse bomb later (#160/#161). Plain Dictionary
## state so the server can sync a whole objective as one small array (pack/unpack).
## Pure helpers: no nodes, no RPCs. The mode helper (shared/ctf.gd) decides who may touch what.

const AT_HOME := 0
const CARRIED := 1
const DROPPED := 2
## Touch zone: horizontal radius (m) and how far above/below the point still counts.
const TOUCH_RADIUS := 1.6
const TOUCH_HEIGHT := 2.2


## New objective resting at `home`.
static func make(home: Vector3) -> Dictionary:
	return {"home": home, "state": AT_HOME, "carrier": 0, "pos": home, "drop_t": 0.0}


## `peer` now carries it.
static func pick_up(o: Dictionary, peer: int) -> void:
	o.state = CARRIED
	o.carrier = peer
	o.drop_t = 0.0


## Left on the ground at `pos`; goes home by itself after `return_after` seconds.
static func drop(o: Dictionary, pos: Vector3, return_after: float) -> void:
	o.state = DROPPED
	o.carrier = 0
	o.pos = pos
	o.drop_t = return_after


## Back on its base.
static func send_home(o: Dictionary) -> void:
	o.state = AT_HOME
	o.carrier = 0
	o.pos = o.home
	o.drop_t = 0.0


## Counts down a dropped objective; true on the tick it returns home by itself.
static func tick(o: Dictionary, delta: float) -> bool:
	if int(o.state) != DROPPED:
		return false
	o.drop_t = float(o.drop_t) - delta
	if float(o.drop_t) <= 0.0:
		send_home(o)
		return true
	return false


## `pos` is inside the touch zone around `center` (a short cylinder).
static func in_zone(pos: Vector3, center: Vector3, radius := TOUCH_RADIUS) -> bool:
	var d := Vector2(pos.x - center.x, pos.z - center.z)
	return d.length() <= radius and absf(pos.y - center.y) <= TOUCH_HEIGHT


## Wire form: [state, carrier, pos, drop_t]. `home` is map data and never travels.
static func pack(o: Dictionary) -> Array:
	return [int(o.state), int(o.carrier), o.pos, float(o.drop_t)]


static func unpack(o: Dictionary, a: Array) -> void:
	if a.size() < 4:
		return
	o.state = int(a[0])
	o.carrier = int(a[1])
	o.pos = a[2]
	o.drop_t = float(a[3])
