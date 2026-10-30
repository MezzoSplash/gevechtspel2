class_name MatchRules
extends RefCounted
## Match rules pulled out of Game (shared/game.gd): scoring per mode, win checks, the round clock and the
## per-round state reset. Static helpers only: Game keeps the state, the constants, every signal and
## every @rpc (round end, scores), so node paths and the network protocol stay the same.


## What counts for a team: kills, or the summed style of its members in style modes.
static func team_score(game: Node, team_id: int) -> int:
	if not game.is_style_mode():
		return game.get_team_kills(team_id)
	var sum := 0
	for id in game.scores:
		if int(game.scores[id].get("team", 0)) == team_id:
			sum += int(game.scores[id].get("style", 0))
	return sum


static func player_score(game: Node, peer_id: int) -> int:
	if not game.scores.has(peer_id):
		return 0
	return int(game.scores[peer_id].get("style" if game.is_style_mode() else "kills", 0))


static func default_kills_for(game: Node, m: int) -> int:
	var mm: int = game.mode if m < 0 else m
	if game.is_style_mode(mm):
		return game.STYLE_FFA_LIMIT if game.is_ffa(mm) else game.STYLE_TDM_LIMIT
	return game.FFA_WIN_KILLS if game.is_ffa(mm) else game.WIN_KILLS


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
	game._bursts.clear()
	game._shotgun_kill_t.clear()
	game._hs_streak.clear()
	game._mags.clear()
