class_name MatchRules
extends RefCounted
## Match rules pulled out of Game (shared/game.gd): scoring per mode, win checks, the round clock and the
## per-round state reset. Static helpers only: Game keeps the state, the constants, every signal and
## every @rpc (round end, scores), so node paths and the network protocol stay the same.


## What counts for a team: kills, or the summed style of its members in style modes.
static func team_score(game: Node, team_id: int) -> int:
	if game.is_ctf():
		return int(game.ctf_caps[clampi(team_id, 0, 1)]) # #160: captures, not kills
	if not game.is_style_mode():
		return game.get_team_kills(team_id)
	var sum := 0
	for id in game.scores:
		if int(game.scores[id].get("team", 0)) == team_id:
			sum += int(game.scores[id].get("style", 0))
	return sum


## Kills, or style in style modes, for one peer.
static func player_score(game: Node, peer_id: int) -> int:
	if not game.scores.has(peer_id):
		return 0
	return int(game.scores[peer_id].get("style" if game.is_style_mode() else "kills", 0))


## Default kill (or style-rate) limit for mode `m` (-1: current mode).
static func default_kills_for(game: Node, m: int) -> int:
	var mm: int = game.mode if m < 0 else m
	if game.is_style_mode(mm):
		return game.STYLE_FFA_LIMIT if game.is_ffa(mm) else game.STYLE_TDM_LIMIT
	return game.FFA_WIN_KILLS if game.is_ffa(mm) else game.WIN_KILLS


## TDM: ends the round when a team reaches the kill limit.
static func check_win_team(game: Node, team_id: int) -> void:
	if not game._round_active:
		return
	if game.get_team_kills(team_id) >= game.win_kills():
		game._end_round_team(team_id)


## #82: in style modes the first team (TDM) or player (FFA) to score_limit() style points wins.
static func check_style_win(game: Node, peer_id: int) -> void:
	if not game.is_style_mode() or not game._round_active or not game.scores.has(peer_id):
		return
	if game.is_ffa():
		if game.player_score(peer_id) >= game.score_limit():
			game._end_round_player(peer_id)
		return
	var t := int(game.scores[peer_id].get("team", 0))
	if game.team_score(t) >= game.score_limit():
		game._end_round_team(t)


## FFA: first player to kill_limit wins the round.
static func check_win_player(game: Node, peer_id: int) -> void:
	if not game._round_active or not game.scores.has(peer_id):
		return
	if int(game.scores[peer_id].kills) >= game.win_kills():
		game._end_round_player(peer_id)


## Most style this round (> 0). Ties: the name that sorts first. {} if nobody has style.
static func style_king(scores: Dictionary) -> Dictionary:
	var best := {}
	for id in scores:
		var st := int(scores[id].get("style", 0))
		if st <= 0:
			continue
		var n := str(scores[id].name)
		if best.is_empty() or st > int(best.style) or (st == int(best.style) and n < str(best.name)):
			best = {"peer_id": int(id), "name": n, "style": st, "team": int(scores[id].get("team", 0))}
	return best


## Advances the round clock; at time-out ends the round for the leader. True when it ended.
static func update_round_timer(game: Node, delta: float) -> bool:
	if not game._round_active:
		return false
	game._round_timer += delta
	if game._round_timer >= game.round_time:
		if game.is_ffa():
			game._end_round_player(game.top_player())
		else:
			game._end_round_team(game._get_leader())
		return true
	return false


## Per-round trick/combo/line state. start_round and reset_session both cleared exactly this list.
static func clear_round_state(game: Node) -> void:
	game.final_kill.clear()
	game.best_trick.clear()
	game._combos.clear()
	game._style_chain.clear()
	game._line_cd.clear()
	game._line_chain.clear()
	game._line_pos.clear()
	game._line_ms.clear()
	game._bursts.clear()
	game._shotgun_kill_t.clear()
	game._hs_streak.clear()
	game._mags.clear()


## Map, mode, kill limit, round length and the bot split for this match, validated and clamped.
## `-1`/`-1.0` means "keep what the menu chose last time" (the menu's own defaults on a fresh install).
## Called by the RPC (sync_match_config), by main.tscn's boot paths and by the menu's live picker.
static func set_config(game: GameState, new_map: StringName, new_mode: int, kills: int = -1, time_sec: float = -1.0,
		bots: int = -1, allies: int = -1, enemies: int = -1) -> void:
	game.map_id = new_map if Maps.has(new_map) else Maps.DEFAULT
	game.mode = clampi(new_mode, game.MODE_TDM, game.MODE_LAST)
	if game.mode == game.MODE_CTF and not CTF.available(game.map_id):
		game.mode = game.MODE_TDM # #160: no flag bases on this map
	if game.mode == game.MODE_CTF:
		CTF.setup(game)
	CtfFlags.ensure(game) # #160: flag visuals only while CTF runs
	game.kill_limit = clampi(kills if kills >= game.KILLS_MIN else game.last_kills, game.KILLS_MIN, game.KILLS_MAX)
	game.round_time = time_sec if time_sec >= 60.0 else float(game.last_time_min * 60)
	game.round_time = clampf(game.round_time, float(game.TIME_MIN_MINUTES * 60), float(game.TIME_MAX_MINUTES * 60))
	game.bot_count = clampi(bots if bots >= 0 else game.last_bots, 0, game.BOT_COUNT_MAX)
	# Team modes may run an uneven match on purpose (you and a friend against ten bots). FFA has no
	# sides, so it always uses the single bot_count.
	if game.is_ffa() or allies < 0 or enemies < 0:
		game.bot_allies = -1
		game.bot_enemies = -1
	else:
		game.bot_allies = clampi(allies, 0, game.BOT_COUNT_MAX)
		game.bot_enemies = clampi(enemies, 0, game.BOT_COUNT_MAX)
	if game.match_config_handler.is_valid():
		game.match_config_handler.call(game.map_id, game.mode)
