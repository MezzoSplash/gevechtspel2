class_name BotStyle
extends Resource
## #267: how a bot fights. Difficulty (`Game.BOT_PROFILES`) says how *good* a bot is - reaction, aim
## wobble, awareness. This says what it *wants*: close in and brawl, or hold a doorway at range.
## One character per bot slot, stable across respawns; the numbers live in `data/bots/*.tres`.

@export var id: StringName = &"chaos"
@export var display_name: String = "chaos"
## Distance this bot wants in a fight: its gun's own fight range times this. Capped at the gun's
## range + CLOSE_ENOUGH_M so a holder never stands outside the distance it is willing to shoot from.
@export var range_scale: float = 1.0
## Too close for comfort: below this it steps back instead of trading. This is the old TOO_CLOSE
## brake - a floor, not a fighting distance, so close-range brawls still happen (#285 review).
@export var back_off_m: float = 4.0
## How far past its preferred distance it may drift before closing in again. 0 = at `range_scale`.
@export var hold_band: float = 2.0
## Break off and sprint out below this HP after a hit. 0 = never.
@export var retreat_hp: float = 40.0
## Chance per grenade check of throwing a frag when the range is right. 0 = never.
@export var nade_chance: float = 0.35
@export var strafe_hold_min: float = 1.3
@export var strafe_hold_max: float = 2.2
## The distance band where sliding into a fight is worth it (BotBrain used to hard-code 4.5-12 m).
## A wide band is a character that keeps sliding: the aggressive bot closes with it, the holder almost
## never gets there. Slice 2 of #267, also what review #285 asked for.
@export var slide_far: float = 4.5
@export var slide_near: float = 12.0
## Slice 2: the flanker. It only opens fire when it has the enemy from the side or the back, and it
## keeps walking the ring instead of going straight at them.
@export var flank_only: bool = false
## Seconds of blocked sight before it gives up circling and attacks from the front anyway.
@export var flank_patience: float = 0.0
## Chance per tick, while standing on its ring point, of taking another angle on the enemy instead of
## standing there. This is "slaat vaker een hoek om".
@export var flank_switch: float = 0.0

## How much further than its gun's fight range a bot may wander and still shoot.
const CLOSE_ENOUGH_M := 4.0

## Slot order. `for_peer()` walks this, so a lobby of eight always mixes the three and a respawn
## keeps the character the bot had (no re-roll: that is what made every life feel the same).
const ORDER: Array[StringName] = [&"aggressive", &"holder", &"flanker", &"chaos"]

static var _loaded := {}


static func by_id(want: StringName) -> BotStyle:
	if _loaded.has(want):
		return _loaded[want]
	var path := "res://data/bots/%s.tres" % want
	var s := load(path) as BotStyle
	if s == null:
		# A missing file must not take the whole bot down, but it also must not look intentional.
		push_warning("BotStyle: %s missing or not a BotStyle, falling back to the defaults" % path)
		s = BotStyle.new()
	_loaded[want] = s
	return s


## Deterministic by peer id: bots are negative (`bot1` = -1), so slot 1 gets the first character.
static func for_peer(peer_id: int) -> BotStyle:
	var i := posmod(absi(peer_id) - 1, ORDER.size())
	return by_id(ORDER[i])
