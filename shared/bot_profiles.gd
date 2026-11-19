class_name BotProfiles
extends RefCounted
## #90 bot difficulty: the three skill profiles and how a launch flag or menu value names them. One
## source for the table; Game keeps BOT_EASY / BOT_PROFILES / ... as aliases and the chosen
## difficulty (server/offline only; bots run there). HARD is how bots played up to v0.4.1.

const EASY := 0
const MEDIUM := 1
const HARD := 2
const IDS := ["easy", "medium", "hard"]
const NAMES := ["Easy", "Medium", "Hard"]
## acquire: s before the first shot on a new target; wobble: × aim hand size; track: aim catch-up (1/s);
## pause: × pause between bursts; nade: × grenade cooldown; streak: s before using an earned streak.
## Awareness: omni: knows where every enemy is, through walls (how bots played up to now; Hard keeps it).
## Without it a bot only knows an enemy it has seen (or been shot by, or heard fire within `hear` metres)
## and walks to the last place it knew them for `memory` seconds, then patrols the navmesh.
## cover (#269): an empty gun is reloaded out of sight. Easy and Medium reload where they stand.
## trick (#278): chance, per wall met on the way, that a bot jumps onto a wallrun wall (BotWall).
const PROFILES := [
	{"acquire": 0.75, "wobble": 2.3, "track": 5.0, "pause": 1.9, "nade": 2.5, "streak": 6.0,
		"omni": false, "memory": 4.0, "hear": 10.0, "cover": false, "trick": 0.0},
	{"acquire": 0.48, "wobble": 1.6, "track": 8.5, "pause": 1.4, "nade": 1.6, "streak": 3.0,
		"omni": false, "memory": 8.0, "hear": 22.0, "cover": false, "trick": 0.3},
	{"acquire": 0.28, "wobble": 1.0, "track": 14.0, "pause": 1.0, "nade": 1.0, "streak": 1.2,
		"omni": true, "memory": 0.0, "hear": 0.0, "cover": true, "trick": 0.7},
]


## The profile for a difficulty, clamped to the table.
static func profile(difficulty: int) -> Dictionary:
	return PROFILES[clampi(difficulty, EASY, HARD)]


## "easy" / "e" / "0" → EASY ... Unknown → -1.
static func parse(raw: String) -> int:
	var s := raw.strip_edges().to_lower()
	if s in ["easy", "e", "0"]:
		return EASY
	if s in ["medium", "normal", "m", "1"]:
		return MEDIUM
	if s in ["hard", "h", "2"]:
		return HARD
	return -1
