class_name Combo
extends RefCounted
## #84 Tony Hawk style combos. Movement moves (seen by the match authority) build a combo: points add
## up, every move adds MULT_STEP to the multiplier, and each move refills the TIME bar. A kill before
## the bar is empty LANDS it: points × multiplier go onto the killer's style, together with that kill's
## own tricks (one award, one popup). The bar running out or dying BAILS it: everything is lost.
## Movement moves are worth nothing on their own; only a landed combo scores (no double counting).

const WALLRUN := &"wallrun"
const WALLJUMP := &"walljump"
const WALL_TO_WALL := &"wall2wall"
const DIVE := &"dive"
const ROLL := &"roll"
const SLIDE := &"slide"
const SURF := &"surf"
const AIR := &"air" # long air time (strafe jumps, drops) without surfing

const POINTS := {
	WALLRUN: 60, WALLJUMP: 80, WALL_TO_WALL: 120, DIVE: 60, ROLL: 40, SLIDE: 30, SURF: 70, AIR: 40,
}
const LABELS := {
	WALLRUN: "WALLRUN", WALLJUMP: "WALL JUMP", WALL_TO_WALL: "WALL TO WALL", DIVE: "DIVE", ROLL: "ROLL",
	SLIDE: "SLIDE", SURF: "SURF", AIR: "AIR",
}
const TIME := 3.0 # s on the bar after each move
const WARN := 0.8 # s left: the bar turns red
const MULT_START := 1.0
const MULT_STEP := 0.5
const MULT_MAX := 6.0
const REPEAT_WINDOW := 3 # the same move again within the last N moves ...
const REPEAT_FACTOR := 0.5 # ... is worth this much and adds no multiplier (no wall-to-wall farming)
const AIR_TIME := 1.0 # s off the ground for an AIR move
const MAX_MOVES := 40


## New empty combo state.
static func fresh() -> Dictionary:
	return {"pts": 0, "mult": MULT_START, "t": 0.0, "moves": []}


static func active(c: Dictionary) -> bool:
	return not c.is_empty() and int(c.get("pts", 0)) > 0 and float(c.get("t", 0.0)) > 0.0


## Adds a move in place; returns the points it added.
static func add_move(c: Dictionary, move: StringName) -> int:
	var base := int(POINTS.get(move, 0))
	if base <= 0:
		return 0
	var moves: Array = c.get("moves", [])
	var recent := moves.slice(maxi(moves.size() - REPEAT_WINDOW, 0))
	var repeat := recent.has(move)
	var add := roundi(base * (REPEAT_FACTOR if repeat else 1.0))
	c.pts = int(c.get("pts", 0)) + add
	if not repeat and not moves.is_empty():
		c.mult = minf(float(c.get("mult", MULT_START)) + MULT_STEP, MULT_MAX)
	moves.append(move)
	if moves.size() > MAX_MOVES:
		moves.pop_front()
	c.moves = moves
	c.t = TIME
	return add


static func value(c: Dictionary) -> int:
	return roundi(float(c.get("pts", 0)) * float(c.get("mult", MULT_START)))


## "WALLRUN > WALL JUMP > WALL TO WALL" (last few moves).
static func label(c: Dictionary, last: int = 4) -> String:
	var moves: Array = c.get("moves", [])
	var parts: PackedStringArray = []
	for m in moves.slice(maxi(moves.size() - last, 0)):
		parts.append(str(LABELS.get(m, str(m).to_upper())))
	return " > ".join(parts)
