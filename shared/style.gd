class_name Style
extends RefCounted
## Trickshots: style points only, never extra damage. The match authority decides on every kill
## (Game.register_kill) from what it knows about both pawns at that moment; everyone gets the result.
##   NOSCOPE      sniper kill without the scope up (humans only: bots never scope)
##   360 NOSCOPE  a noscope after the shooter turned a full circle within SPIN_WINDOW before the shot
##   AIRSHOT      shooter or victim off the ground for at least AIR_MIN_TIME (so steps/bumps never count)
##   LONGSHOT     at least LONGSHOT_M from the shooter's eye to the victim
## Tricks on one kill stack (a 360 noscope airshot is 250 + 75). Trick kills chained within CHAIN_WINDOW
## add CHAIN_STEP to a multiplier, up to CHAIN_MAX.

const NOSCOPE := &"noscope"
const SPIN := &"360noscope"
const AIRSHOT := &"airshot"
const LONGSHOT := &"longshot"

const POINTS := {NOSCOPE: 100, SPIN: 250, AIRSHOT: 75, LONGSHOT: 50}
const LABELS := {NOSCOPE: "NOSCOPE", SPIN: "360 NOSCOPE", AIRSHOT: "AIRSHOT", LONGSHOT: "LONGSHOT"}
const ORDER: Array[StringName] = [SPIN, NOSCOPE, AIRSHOT, LONGSHOT] # biggest first in popups/feed

const SPIN_DEG := 360.0
const SPIN_WINDOW := 1.0 # seconds before the shot
const SPIN_NET_SLACK := 0.15 # remote humans: their turn reaches the server a little after the shot RPC
const AIR_MIN_TIME := 0.3 # seconds off the ground (a jump is ~0.7 s, a stair step < 0.1 s)
const AIR_GAP := 0.3 # metres of free space under the feet that count as "off the ground"
const LONGSHOT_M := 38.0 # both maps are ~50 x 75 m: spawn to spawn ~65 m, most fights 10-30 m
const CHAIN_WINDOW := 8.0 # seconds between trick kills that still chain
const CHAIN_STEP := 0.25
const CHAIN_MAX := 2.0
const GUNS: Array[StringName] = [&"rifle", &"pistol", &"shotgun", &"sniper"] # melee/grenade kills: no tricks


## Which tricks a kill was. `spin_deg` is the shooter's largest one-way turn in the window before the shot.
static func detect(
	weapon_id: StringName,
	scoped: bool,
	shooter_is_bot: bool,
	spin_deg: float,
	shooter_air_t: float,
	victim_air_t: float,
	dist_m: float
) -> Array[StringName]:
	var out: Array[StringName] = []
	if not GUNS.has(weapon_id):
		return out
	if weapon_id == &"sniper" and not scoped and not shooter_is_bot:
		out.append(SPIN if spin_deg >= SPIN_DEG else NOSCOPE)
	if shooter_air_t >= AIR_MIN_TIME or victim_air_t >= AIR_MIN_TIME:
		out.append(AIRSHOT)
	if dist_m >= LONGSHOT_M:
		out.append(LONGSHOT)
	return out


static func base_points(tricks: Array) -> int:
	var sum := 0
	for t in tricks:
		sum += int(POINTS.get(t, 0))
	return sum


## chain = how many trick kills in a row (this one included) within CHAIN_WINDOW of each other.
static func chain_multiplier(chain: int) -> float:
	return minf(1.0 + CHAIN_STEP * float(maxi(chain - 1, 0)), CHAIN_MAX)


static func award(tricks: Array, chain: int) -> int:
	return roundi(float(base_points(tricks)) * chain_multiplier(chain))


## "360 NOSCOPE + AIRSHOT" (biggest first).
static func label(tricks: Array) -> String:
	var parts: PackedStringArray = []
	for t in ORDER:
		if tricks.has(t):
			parts.append(str(LABELS[t]))
	return " + ".join(parts)


## Wire format: "360noscope,airshot" <-> [&"360noscope", &"airshot"]; unknown ids are dropped.
static func pack(tricks: Array) -> String:
	var parts: PackedStringArray = []
	for t in tricks:
		parts.append(str(t))
	return ",".join(parts)


static func unpack(s: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for part in s.split(",", false):
		var id := StringName(part.strip_edges())
		if POINTS.has(id) and not out.has(id):
			out.append(id)
	return out


## Largest one-way turn (degrees) over any stretch that ends now, within `window` seconds.
## `samples` is [[t, signed_yaw_delta_rad], ...] oldest first.
static func spin_degrees(samples: Array, now: float, window: float) -> float:
	var sum := 0.0
	var best := 0.0
	for i in range(samples.size() - 1, -1, -1):
		var s: Array = samples[i]
		if float(s[0]) < now - window:
			break
		sum += float(s[1])
		best = maxf(best, absf(sum))
	return rad_to_deg(best)
