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
## How far it may drift from that distance before correcting, in metres. Small = it fights at one
## distance, large = it wanders while it trades.
@export var hold_band: float = 2.0
## Break off and sprint out below this HP after a hit. 0 = never.
@export var retreat_hp: float = 40.0
## Chance per grenade check of throwing a frag when the range is right. 0 = never.
@export var nade_chance: float = 0.35
@export var strafe_hold_min: float = 1.3
@export var strafe_hold_max: float = 2.2

## How much further than its gun's fight range a bot may wander and still shoot.
const CLOSE_ENOUGH_M := 4.0

## Slot order. `for_peer()` walks this, so a lobby of eight always mixes the three and a respawn
## keeps the character the bot had (no re-roll: that is what made every life feel the same).
const ORDER: Array[StringName] = [&"aggressive", &"holder", &"chaos"]

static var _loaded := {}


static func by_id(want: StringName) -> BotStyle:
	if _loaded.has(want):
		return _loaded[want]
	var path := "res://data/bots/%s.tres" % want
	var s := load(path) as BotStyle
	if s == null:
		s = BotStyle.new() # a missing file must not take the whole bot down
	_loaded[want] = s
	return s


## Deterministic by peer id: bots are negative (`bot1` = -1), so slot 1 gets the first character.
static func for_peer(peer_id: int) -> BotStyle:
	var i := posmod(absi(peer_id) - 1, ORDER.size())
	return by_id(ORDER[i])
