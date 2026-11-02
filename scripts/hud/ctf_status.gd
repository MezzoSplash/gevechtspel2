class_name CtfStatus
extends RefCounted
## #160 HUD text for CTF: the score line under the clock and the popup for a flag event.
## Static and string-only, so the HUD stays thin and the check can test the wording.


## "BLUE 1 - 0 ORANGE  ·  first to 3" plus both flag states, and a hint when you carry the flag.
static func line(g: Node, my_peer: int) -> String:
	if g.flags.size() != 2:
		return ""
	var s := "BLUE %d - %d ORANGE  ·  first to %d" % [int(g.ctf_caps[0]), int(g.ctf_caps[1]), CTF.CAPTURES_TO_WIN]
	s += "\n%s   |   %s" % [CTF.status_text(g, 0), CTF.status_text(g, 1)]
	for t in 2:
		if int(g.flags[t].carrier) == my_peer and my_peer != 0:
			s += "\nYOU HAVE THE FLAG: RUN HOME"
	return s


## Popup title for a flag event: e.g. "ORANGE FLAG TAKEN", "BLUE SCORES".
static func popup_title(kind: String, flag_team: int) -> String:
	var flag: String = CTF.TEAM_NAMES[clampi(flag_team, 0, 1)]
	match kind:
		"captured":
			return "%s SCORES" % CTF.TEAM_NAMES[1 - clampi(flag_team, 0, 1)]
		"taken":
			return "%s FLAG TAKEN" % flag
		"dropped":
			return "%s FLAG DROPPED" % flag
	return "%s FLAG RETURNED" % flag


## Team of whoever caused the event: the enemy of the flag, except a return (the flag's own team).
static func actor_team(kind: String, flag_team: int) -> int:
	return flag_team if kind == "returned" else 1 - flag_team


## Good news for `my_team`?
static func is_good(kind: String, flag_team: int, my_team: int) -> bool:
	return actor_team(kind, flag_team) == my_team if kind != "dropped" else flag_team == my_team
