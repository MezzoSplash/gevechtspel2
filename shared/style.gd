class_name Style
extends RefCounted
## Trickshots: style points only, never extra damage. The match authority decides on every kill
## (Game.register_kill) from what it knows about both pawns at that moment; everyone gets the result.
## Sniper
##   NOSCOPE         sniper kill without the scope up (humans only: bots never scope)
##   360 NOSCOPE     a noscope after the shooter turned a full circle within SPIN_WINDOW before the shot
## Shotgun
##   POINT BLANK     shotgun kill within POINT_BLANK_M while airborne, sprinting or sliding
##   DOUBLE          a second shotgun kill from the same shot or within DOUBLE_WINDOW
## Rifle
##   SPRAY TRANSFER  a kill on a new victim in the same held-trigger burst as an earlier kill
##   HEADSHOT STREAK the HS_STREAK_KILLS-th (and every further) headshot kill in a row with the rifle
## SMG
##   RUN & GUN       kill while sprinting or air-strafing: shooter above RUN_GUN_SPEED for RUN_GUN_TIME without stopping
##   HOSE            the HOSE_KILLS-th (and further) kill from one magazine, no reload in between
## Revolver
##   QUICKDRAW       kill within QUICKDRAW_TIME after switching to the revolver
##   SIX SHOOTER     the SIX_KILLS-th kill from one cylinder (six rounds, no reload)
## Throwing knife
##   YEET            throwing-knife kill; YEET x2 (double points) if the thrower was airborne or surfing at the throw
## Any gun
##   AIRSHOT         shooter or victim off the ground for at least AIR_MIN_TIME (steps/bumps never count)
##   LONGSHOT        at least LONGSHOT_M from the shooter's eye to the victim
## Any gun or melee
##   SURF KILL       the shooter is surfing (on a ramp steeper than walkable) when the kill lands
##   DROP KILL       the shooter is falling, or landed within DROP_RECENT, after dropping DROP_M or more
## Tricks on one kill stack. Trick kills chained within CHAIN_WINDOW add CHAIN_STEP to a multiplier,
## up to CHAIN_MAX. Surfing or dropping is the shooter's own "air", so it replaces the shooter half of
## AIRSHOT (an airborne victim still counts).

const NOSCOPE := &"noscope"
const SPIN := &"360noscope"
const AIRSHOT := &"airshot"
const LONGSHOT := &"longshot"
const POINT_BLANK := &"pointblank"
const DOUBLE := &"double"
const SPRAY := &"spraytransfer"
const HS_STREAK := &"hsstreak"
const SURF := &"surf"
const DROP := &"drop"
const RUN_GUN := &"rungun"
const HOSE := &"hose"
const QUICKDRAW := &"quickdraw"
const SIX_SHOOTER := &"sixshooter"
const YEET := &"yeet"
const YEET_X2 := &"yeet2" # replaces YEET (500 = double)

## A good rifle or shotgun play lands near a 360 noscope (250): a slide point blank double is
## 100 + 150, a spray transfer 150 (x chain), the third headshot in a row 200.
const POINTS := {
	NOSCOPE: 100, SPIN: 250, AIRSHOT: 75, LONGSHOT: 50,
	POINT_BLANK: 100, DOUBLE: 150, SPRAY: 150, HS_STREAK: 200, SURF: 150, DROP: 100,
	RUN_GUN: 125, HOSE: 150, QUICKDRAW: 150, SIX_SHOOTER: 200, YEET: 250, YEET_X2: 500,
}
const LABELS := {
	NOSCOPE: "NOSCOPE", SPIN: "360 NOSCOPE", AIRSHOT: "AIRSHOT", LONGSHOT: "LONGSHOT",
	POINT_BLANK: "POINT BLANK", DOUBLE: "DOUBLE", SPRAY: "SPRAY TRANSFER", HS_STREAK: "HEADSHOT STREAK",
	SURF: "SURF KILL", DROP: "DROP KILL",
	RUN_GUN: "RUN & GUN", HOSE: "HOSE", QUICKDRAW: "QUICKDRAW", SIX_SHOOTER: "SIX SHOOTER",
	YEET: "YEET", YEET_X2: "YEET ×2",
}
## Biggest first in popups and the kill feed.
const ORDER: Array[StringName] = [
	YEET_X2, YEET, SPIN, HS_STREAK, SIX_SHOOTER, NOSCOPE, SPRAY, DOUBLE, HOSE, QUICKDRAW, SURF,
	RUN_GUN, POINT_BLANK, DROP, AIRSHOT, LONGSHOT,
]

const SPIN_DEG := 360.0
const SPIN_WINDOW := 1.0 # seconds before the shot
const SPIN_NET_SLACK := 0.15 # remote humans: their turn reaches the server a little after the shot RPC
const AIR_MIN_TIME := 0.3 # seconds off the ground (a jump is ~0.7 s, a stair step < 0.1 s)
const AIR_GAP := 0.3 # metres of free space under the feet that count as "off the ground"
const LONGSHOT_M := 38.0 # both maps are ~50 x 75 m: spawn to spawn ~65 m, most fights 10-30 m
const POINT_BLANK_M := 3.0 # eye to the victim's body
const POINT_BLANK_SPEED := 8.5 # m/s ground speed: walking is 7.6, sprint 11.4, a slide starts at 11.4
const DOUBLE_WINDOW := 1.0 # seconds between two shotgun kills (one shot can kill two: 0 s)
const BURST_GAP := 0.5 # seconds: a longer pause between rifle shots ends the burst even if the trigger stayed down
const HS_STREAK_KILLS := 3
const SURF_RECENT := 0.3 # seconds since the last ramp contact that still count as surfing
const DROP_M := 3.5 # metres from the highest point of the fall: a jump off an upper floor (3 m) clears it, a jump on flat ground (~1.3 m) does not
const DROP_RECENT := 1.0 # seconds after landing
const RUN_GUN_SPEED := 9.0 # m/s: SMG walk is 8.2, SMG sprint 12.3; bunny hops and slides stay above it
const RUN_GUN_TIME := 0.5 # s at that speed without dropping below it (a stop-and-shoot never counts)
const HOSE_KILLS := 2
const QUICKDRAW_TIME := 0.4 # s from the switch to the kill
const QUICKDRAW_NET_SLACK := 0.1 # remote humans: the switch and the shot reach the server with some jitter
const SIX_KILLS := 3
const CHAIN_WINDOW := 8.0 # seconds between trick kills that still chain
const CHAIN_STEP := 0.25
const CHAIN_MAX := 2.0
const GUNS: Array[StringName] = [&"rifle", &"pistol", &"shotgun", &"sniper", &"smg", &"revolver"] # grenade kills: no tricks
const MOVE_WEAPONS: Array[StringName] = [&"rifle", &"pistol", &"shotgun", &"sniper", &"smg", &"revolver", &"melee"]


## Which tricks a kill was. `c` (all optional):
##   weapon (StringName), scoped, bot, headshot (bool), spin (deg, largest one-way turn before the shot),
##   shooter_air / victim_air (s off the ground), dist (m), speed (shooter ground m/s),
##   surf (shooter is surfing), drop (m the shooter fell, if recent), burst_victims (others already
##   killed in this rifle burst), double (another shotgun kill within DOUBLE_WINDOW),
##   hs_streak (rifle headshot kills in a row, this one included),
##   run_t (s the shooter has stayed above RUN_GUN_SPEED), mag_kills (kills from this magazine, this one
##   included), since_draw (s since the held gun was switched to; INF = not drawn), quickdraw_slack,
##   knife_air (thrower airborne or surfing at the throw).
static func detect(c: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var weapon := StringName(c.get("weapon", &""))
	var gun := GUNS.has(weapon)
	var surf := bool(c.get("surf", false))
	var drop := float(c.get("drop", 0.0)) >= DROP_M
	if gun and weapon == &"sniper" and not bool(c.get("scoped", false)) and not bool(c.get("bot", false)):
		out.append(SPIN if float(c.get("spin", 0.0)) >= SPIN_DEG else NOSCOPE)
	if weapon == &"shotgun":
		var moving := float(c.get("shooter_air", 0.0)) >= AIR_MIN_TIME or float(c.get("speed", 0.0)) >= POINT_BLANK_SPEED
		if float(c.get("dist", INF)) <= POINT_BLANK_M and (moving or surf or drop):
			out.append(POINT_BLANK)
		if bool(c.get("double", false)):
			out.append(DOUBLE)
	if weapon == &"rifle":
		if int(c.get("burst_victims", 0)) >= 1:
			out.append(SPRAY)
		if bool(c.get("headshot", false)) and int(c.get("hs_streak", 0)) >= HS_STREAK_KILLS:
			out.append(HS_STREAK)
	if weapon == &"smg":
		if float(c.get("run_t", 0.0)) >= RUN_GUN_TIME and float(c.get("speed", 0.0)) >= RUN_GUN_SPEED:
			out.append(RUN_GUN)
		if int(c.get("mag_kills", 0)) >= HOSE_KILLS:
			out.append(HOSE)
	if weapon == &"revolver":
		if float(c.get("since_draw", INF)) <= QUICKDRAW_TIME + float(c.get("quickdraw_slack", 0.0)):
			out.append(QUICKDRAW)
		if int(c.get("mag_kills", 0)) >= SIX_KILLS:
			out.append(SIX_SHOOTER)
	if weapon == &"knife":
		out.append(YEET_X2 if bool(c.get("knife_air", false)) else YEET)
	if MOVE_WEAPONS.has(weapon):
		if surf:
			out.append(SURF)
		if drop:
			out.append(DROP)
	if gun:
		var shooter_air := float(c.get("shooter_air", 0.0)) >= AIR_MIN_TIME and not surf and not drop
		if shooter_air or float(c.get("victim_air", 0.0)) >= AIR_MIN_TIME:
			out.append(AIRSHOT)
		if float(c.get("dist", 0.0)) >= LONGSHOT_M:
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
