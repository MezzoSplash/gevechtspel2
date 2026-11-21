extends Node
## BotRoster (shared/bot_roster.gd): which team gets the next bot and which bot goes, on loose pawns
## without a match. Balanced fill (one total, smaller team first, trim from the larger team), the split
## (a target per side that a joining human never shrinks), the dedicated server refusing the split, and
## a pawn queued for deletion no longer counting. check_tdm_team_setup drives the same through the menu.
##   godot --headless res://tools/check_bot_roster.tscn
var fails := 0
var _made: Array[Player] = []


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _pawn(team: int, bot: bool) -> Player:
	var p := Player.new()
	p.team_id = team
	p.is_bot = bot
	_made.append(p)
	return p


## Fills `pawns` the way main.gd does: ask, add one, ask again (bounded).
func _fill(pawns: Array) -> int:
	var added := 0
	for _i in GameState.BOT_COUNT_MAX * 2:
		var team := BotRoster.team_to_fill(Game, pawns)
		if team < 0:
			break
		pawns.append(_pawn(team, true))
		added += 1
	return added


## Trims `pawns` the way main.gd does (drop = leave the array; main.gd frees the node instead).
func _trim(pawns: Array) -> int:
	var dropped := 0
	for _i in GameState.BOT_COUNT_MAX * 2:
		var bot := BotRoster.bot_to_drop(Game, pawns)
		if bot == null:
			break
		pawns.erase(bot)
		dropped += 1
	return dropped


func _ready() -> void:
	var A := GameState.TEAM_A
	var B := GameState.TEAM_B
	var was_dedicated := Game.is_dedicated
	var was_mode := Game.mode
	Game.is_dedicated = false

	# --- balanced: one total, each bot on the smaller team.
	Game.mode = Game.MODE_TDM
	Game.bot_allies = -1
	Game.bot_enemies = -1
	Game.bot_count = 5
	var pawns: Array = [_pawn(A, false)]
	_ok(not BotRoster.split_active(Game) and BotRoster.target(Game, A) == -1, "no allies/enemies: balanced, no target")
	_ok(_fill(pawns) == 5, "fills to bot_count (5)")
	_ok(BotRoster.count(pawns, A) == 3 and BotRoster.count(pawns, B) == 3,
		"you + 5 bots is 3 v 3 (%d/%d)" % [BotRoster.count(pawns, A), BotRoster.count(pawns, B)])
	_ok(BotRoster.team_to_fill(Game, pawns) == -1, "full: nothing more to fill")
	pawns.append(_pawn(B, false))
	_ok(_trim(pawns) == 0, "bots at bot_count: a human joining trims nothing by itself")
	Game.bot_count = 4
	_ok(_trim(pawns) == 1 and BotRoster.count(pawns, A, 1) == 2 and BotRoster.count(pawns, B, 1) == 2,
		"one over: the bot goes from the larger side (bots %d/%d)" % [BotRoster.count(pawns, A, 1), BotRoster.count(pawns, B, 1)])
	Game.bot_count = 0
	_ok(_trim(pawns) == 4 and BotRoster.count(pawns, GameState.TEAM_A, 1) + BotRoster.count(pawns, B, 1) == 0, "bot_count 0 trims every bot")
	_ok(BotRoster.count(pawns, BotRoster.ANY, 0) == 2, "and never a human")

	# --- the split: 0 with you, 10 against, and a friend joining keeps all ten.
	Game.bot_team_base = A
	Game.bot_allies = 0
	Game.bot_enemies = 10
	Game.bot_count = 10
	pawns = [_pawn(A, false)]
	_ok(BotRoster.split_active(Game), "allies 0 / enemies 10 runs the split")
	_ok(BotRoster.target(Game, A) == 0 and BotRoster.target(Game, B) == 10, "targets follow bot_team_base")
	_ok(_fill(pawns) == 10 and BotRoster.count(pawns, B, 1) == 10 and BotRoster.count(pawns, A, 1) == 0, "ten bots, all against you")
	pawns.append(_pawn(A, false))
	_ok(_trim(pawns) == 0, "a friend joining your side keeps the ten")
	Game.bot_enemies = 7
	_ok(_trim(pawns) == 3 and BotRoster.count(pawns, B, 1) == 7, "a lower target trims only that side down to it")
	Game.bot_team_base = B
	_ok(BotRoster.target(Game, B) == 0 and BotRoster.target(Game, A) == 7, "allies move with the side you picked")
	Game.bot_team_base = A

	# --- who refuses the split.
	Game.is_dedicated = true
	_ok(not BotRoster.split_active(Game), "a dedicated server balances")
	Game.is_dedicated = false
	Game.mode = Game.MODE_FFA
	_ok(not BotRoster.split_active(Game), "FFA has no sides")
	Game.mode = Game.MODE_TDM
	Game.bot_allies = 0
	Game.bot_enemies = 0
	_ok(not BotRoster.split_active(Game), "0 and 0 is no split")

	# --- a pawn on its way out no longer counts (main.gd frees, then asks again in the same frame).
	Game.bot_allies = -1
	Game.bot_enemies = -1
	Game.bot_count = 1
	var gone := _pawn(A, true)
	pawns = [gone]
	gone.queue_free()
	_made.erase(gone) # freed at the end of the frame, not by the cleanup below
	_ok(BotRoster.count(pawns) == 0 and BotRoster.first_bot_on(pawns, A) == null, "queued for deletion is gone")
	_ok(BotRoster.team_to_fill(Game, pawns) == A, "so the fill replaces it")
	var plain := Node.new()
	_ok(BotRoster.count([plain]) == 0, "a node that is no pawn is not counted")
	plain.free()

	# --- Game's old names are the same answers.
	Game.bot_allies = 2
	Game.bot_enemies = 6
	_ok(Game.bot_split_active() == BotRoster.split_active(Game) and Game.bot_target(B) == 6, "Game.bot_split_active / bot_target wrap it")

	Game.is_dedicated = was_dedicated
	Game.mode = was_mode
	for p in _made:
		p.free()
	print("BOT ROSTER CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
