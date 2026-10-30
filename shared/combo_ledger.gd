class_name ComboLedger
extends RefCounted
## Combo bookkeeping (#84) and style awarding, pulled out of Game (shared/game.gd).
## Static helpers only: Game keeps the state (_combos, _style_chain, best_trick, scores) and every
## @rpc (sync_combo, sync_trick), so node paths and the network protocol stay the same.


## Points (with the chain multiplier) onto the killer's style; tell everyone; remember the round's best
## trick for the final killcam.
static func award_style(game: Node, kill_info: Dictionary, tricks_in: Array[StringName]) -> void:
	var k := int(kill_info.k)
	var tricks: Array[StringName] = tricks_in.duplicate()
	var bank := 0
	var c: Dictionary = game._combos.get(k, {})
	if Combo.active(c):
		bank = Combo.value(c) # #84: the kill lands the combo
		tricks.append(Style.COMBO)
		end(game, k, "landed", bank)
	var now := Time.get_ticks_msec() / 1000.0
	var chain := Tricks.next_chain(game._style_chain, k, now)
	var pts := Style.award(tricks, chain) + bank # chain multiplier on the kill tricks only, never on the combo
	var mult := Style.chain_multiplier(chain)
	var total := pts + (int(game.scores[k].get("style", 0)) if game.scores.has(k) else 0)
	game._trick_seq += 1
	# Best trickshot = the biggest single landed combo (its payout, points × multiplier) of the round, over
	# all players. Kills without a combo only count while nobody has landed one yet. Before this a plain
	# trick kill with a chain multiplier (e.g. a bot's HOSE + RUN & GUN ×2) could beat a bigger combo.
	var is_best := Tricks.is_best(game.best_trick, game._round_active, bank, pts)
	if is_best:
		var bt: Dictionary = kill_info.duplicate()
		bt["pts"] = pts
		bt["bank"] = bank
		bt["tags"] = Style.label(tricks) # #88: with COMBO, so a combo-landing best does not look like a plain kill
		bt["trick_id"] = game._trick_seq
		game.best_trick = bt
	var packed := Style.pack(tricks)
	game._apply_trick(k, int(kill_info.v), packed, pts, mult, total, game._trick_seq, is_best)
	if game.is_networked():
		game.sync_trick.rpc(k, int(kill_info.v), packed, pts, mult, total, game._trick_seq, is_best)


static func move(game: Node, peer_id: int, move_id: StringName) -> void:
	if not game._is_match_authority() or not game._round_active or game.play_locked() or not game.scores.has(peer_id):
		return
	var c: Dictionary = game._combos.get(peer_id, {})
	if not Combo.active(c):
		c = Combo.fresh()
	if Combo.add_move(c, move_id) <= 0:
		return
	game._combos[peer_id] = c
	send(game, peer_id, c, "build", 0)


## Death, a timeout, a landing: the combo is over either way.
static func end(game: Node, peer_id: int, state: String, banked: int) -> void:
	var c: Dictionary = game._combos.get(peer_id, {})
	game._combos.erase(peer_id)
	if c.is_empty():
		return
	send(game, peer_id, c, state, banked)


static func tick(game: Node, delta: float) -> void:
	if game._combos.is_empty() or not game._is_match_authority():
		return
	for id in game._combos.keys():
		var c: Dictionary = game._combos[id]
		# #89: surfing holds the clock (a long surf is the trick, not a pause). The HUD shows it frozen.
		var pawn: Player = game.player_for_peer(int(id))
		var surfing := pawn != null and not pawn.is_dead and pawn.style_surfing()
		if surfing != bool(c.get("frozen", false)):
			c["frozen"] = surfing
			send(game, int(id), c, "build", 0) # "frozen" while c.frozen, see send
		if surfing:
			continue
		c.t = float(c.t) - delta
		if float(c.t) <= 0.0:
			end(game, id, "bailed", 0)


static func send(game: Node, peer_id: int, c: Dictionary, state: String, banked: int) -> void:
	if state == "build" and bool(c.get("frozen", false)):
		state = "frozen" # a move while surfing: new points, the timer is still held
	var args := [int(c.get("pts", 0)), float(c.get("mult", 1.0)), maxf(float(c.get("t", 0.0)), 0.0), Combo.label(c), state, banked]
	if not game.is_networked() or peer_id == game.multiplayer.get_unique_id():
		game._apply_combo(args)
	elif peer_id > 0 and peer_id in game.multiplayer.get_peers():
		game.sync_combo.rpc_id(peer_id, args)
