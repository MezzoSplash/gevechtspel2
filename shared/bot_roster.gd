class_name BotRoster
extends RefCounted
## How many bots a match keeps and on which side (#316 slice 8: from Game and main.gd). Static and pure:
## it reads the match's numbers off Game (bot_count, bot_allies, bot_enemies, bot_team_base, set by
## MatchRules.set_config and main.gd) and the pawns it is handed, and answers which team gets the next
## bot and which bot goes. main.gd still spawns and frees the pawns; Game keeps the state and its old
## names (bot_split_active, bot_target) as wrappers.
##
## Two ways to fill. Balanced: one total (bot_count), each new bot on the smaller team and each extra
## one taken from the larger, so humans joining trim the bots. Split (team modes, local or listen host):
## a target per side, "you and a friend against ten bots", and a joining human never shrinks it.

const ANY := -1 ## count(): every team


## True when this match fills bots per team instead of balancing one total.
static func split_active(game: GameState) -> bool:
	# A dedicated server always balances: it has no owner whose side the allies would be on, and the
	# per-side fill would keep every bot when humans join, so a public server would fill up with ten
	# bots plus ten players. Local and listen-host matches run the split.
	if game.is_dedicated:
		return false
	return not game.is_ffa() and game.bot_allies >= 0 and game.bot_enemies >= 0 \
		and (game.bot_allies + game.bot_enemies) > 0


## Bots wanted on `team`: the allies sit on bot_team_base, everyone else is an enemy bot. -1 = no split.
static func target(game: GameState, team: int) -> int:
	if game.bot_allies < 0:
		return -1
	return game.bot_allies if team == game.bot_team_base else game.bot_enemies


## Live pawns among `pawns` (any Node; a pawn queued for deletion is gone already). `bots`: 1 = bots
## only, 0 = humans only, -1 = both. `team` ANY counts every team.
static func count(pawns: Array, team: int = ANY, bots: int = -1) -> int:
	var n := 0
	for child in pawns:
		if _live(child, team, bots):
			n += 1
	return n


## The first live bot on `team`, null when there is none.
static func first_bot_on(pawns: Array, team: int) -> Player:
	for child in pawns:
		if _live(child, team, 1):
			return child as Player
	return null


## TEAM_A unless TEAM_B has fewer pawns (bots and humans), as the balanced fill has always done.
static func smaller_team(pawns: Array) -> int:
	if count(pawns, GameState.TEAM_A) <= count(pawns, GameState.TEAM_B):
		return GameState.TEAM_A
	return GameState.TEAM_B


## TEAM_A unless TEAM_B has more pawns.
static func larger_team(pawns: Array) -> int:
	if count(pawns, GameState.TEAM_A) >= count(pawns, GameState.TEAM_B):
		return GameState.TEAM_A
	return GameState.TEAM_B


## The team the next bot spawns on, -1 when the roster is full. main.gd spawns it and asks again.
static func team_to_fill(game: GameState, pawns: Array) -> int:
	if split_active(game):
		for team in [GameState.TEAM_A, GameState.TEAM_B]:
			var want := target(game, team)
			if want >= 0 and count(pawns, team, 1) < want:
				return team
		return -1
	if count(pawns, ANY, 1) < game.bot_count:
		return smaller_team(pawns)
	return -1


## The bot to drop next, null when nothing is over. A split takes from a side above its own target
## only; the balanced fill takes from the larger team down to bot_count in total.
static func bot_to_drop(game: GameState, pawns: Array) -> Player:
	if split_active(game):
		for team in [GameState.TEAM_A, GameState.TEAM_B]:
			var want := target(game, team)
			if want >= 0 and count(pawns, team, 1) > want:
				var over := first_bot_on(pawns, team)
				if over:
					return over
		return null
	if count(pawns, ANY, 1) <= game.bot_count:
		return null
	var bot := first_bot_on(pawns, larger_team(pawns))
	if bot == null:
		bot = first_bot_on(pawns, GameState.TEAM_A)
	if bot == null:
		bot = first_bot_on(pawns, GameState.TEAM_B)
	return bot


static func _live(child: Variant, team: int, bots: int) -> bool:
	var p := child as Player
	if p == null or p.is_queued_for_deletion():
		return false
	if team != ANY and p.team_id != team:
		return false
	return bots < 0 or p.is_bot == (bots == 1)
