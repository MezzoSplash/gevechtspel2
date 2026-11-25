class_name Streaks
extends RefCounted
## Scorestreaks (#106): kill counts, UAV / RC-XD charges, using a charge, the UAV radar. Static helpers on
## the Game autoload `g`; Game keeps the state and every @rpc (sync_streak, sync_radar, ...).


## Humans and bots (bots have negative ids). Death clears this life's count, not a streak already earned.
## The player's pick (#387) decides which streaks bank: 3 banks the UAV, 5 the RC-XD, 7 LOS by default,
## and a slot holds whatever was picked for it. Each stays until Enter uses it, or until start_round
## clears every charge for the next round. Bots never bank LOS: they do not pilot the hands.
static func bump_streak(g: GameState, killer_peer_id: int, victim_peer_id: int) -> void:
	if victim_peer_id != 0:
		g.streak_progress[victim_peer_id] = 0
		g.streak_earned[victim_peer_id] = 0
		push_streak(g, victim_peer_id)
	if killer_peer_id == 0:
		return
	var n := int(g.streak_progress.get(killer_peer_id, 0))
	# The counter runs to the most expensive streak the player picked, and never past LOS's 7
	# (the old cap) so an unchanged pick counts exactly as before.
	if n < maxi(g.LOS_AT, top_cost(g, killer_peer_id)):
		n += 1
	g.streak_progress[killer_peer_id] = n
	var charges := int(g.streak_charges.get(killer_peer_id, 0))
	var earned := int(g.streak_earned.get(killer_peer_id, 0))
	# #387: the chosen streaks, not the fixed three. A bit stays keyed by id, so an unchanged pick
	# banks exactly what it did before. Bots never bank LOS: they do not pilot the hands.
	for raw in StreakSelect.choice_for(g, killer_peer_id):
		var id := StringName(raw)
		var bit := StreakDefs.bit(id)
		if bit == 0 or n < StreakDefs.kills(id) or (earned & bit) != 0:
			continue
		if bit == g.CHARGE_LOS and killer_peer_id < 0:
			continue # bots do not pilot the hands; Overdrive is fine for them (#388)
		earned |= bit
		charges |= bit
	g.streak_earned[killer_peer_id] = earned
	g.streak_charges[killer_peer_id] = charges
	push_streak(g, killer_peer_id)


## The most expensive streak in a peer's pick; 0 when the pick is empty.
static func top_cost(g: GameState, peer_id: int) -> int:
	var top := 0
	for raw in StreakSelect.choice_for(g, peer_id):
		top = maxi(top, StreakDefs.kills(StringName(raw)))
	return top


## Sends one peer its streak state: HUD locally, RPC to a remote human; bots have no HUD.
static func push_streak(g: GameState, peer_id: int) -> void:
	var n := int(g.streak_progress.get(peer_id, 0))
	var charges := int(g.streak_charges.get(peer_id, 0))
	var earned := int(g.streak_earned.get(peer_id, 0))
	if peer_id < 0:
		return # bot: its brain reads streak_charges on the server, no HUD to update
	if not g.is_networked() or peer_id == g.multiplayer.get_unique_id():
		apply_streak_local(g, n, charges, earned)
		return
	g.sync_streak.rpc_id(peer_id, n, charges, earned)


## Shows the streak counter and charges on this machine's HUD.
static func apply_streak_local(g: GameState, n: int, charges: int, earned: int) -> void:
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_streak(n, charges, earned)


## A slot fires the streak the player picked for it (#387): UAV/RC-XD/LOS in the default order.
## Using one spends only that charge.
## UAV still spends if one is already running (time is not stacked).
## Freeze, killcam, death, a car already out, or hands already out: the charge is kept.
## LOS and the RC-XD never run together. A failed launch (bot, dead, the other streak) does not spend.
static func try_activate_streak(g: GameState, peer_id: int, slot: int) -> void:
	if not g._is_match_authority():
		return
	if g.play_locked() or peer_id == 0:
		return
	var p := g.player_for_peer(peer_id)
	if p == null or p.is_dead:
		return
	if RcXd.for_owner(peer_id) != null or LosHands.for_owner(peer_id) != null:
		return
	# #388: one Overdrive at a time; activating again refreshes the clock instead of stacking.
	var already_over := Overdrive.for_owner(peer_id) != null
	# #387: the slot holds whatever streak the player picked for it, not a fixed UAV/RC-XD/LOS.
	var id := StreakSelect.id_at(g, peer_id, slot)
	var bit := StreakDefs.bit(id)
	if bit == 0:
		return
	var charges := int(g.streak_charges.get(peer_id, 0))
	if (charges & bit) == 0:
		return
	if bit == g.CHARGE_RCXD and not RcXd.launch(p):
		return
	if bit == g.CHARGE_LOS and not LosHands.launch(p):
		return
	if bit == g.CHARGE_OVERDRIVE and not Overdrive.launch(p):
		return
	if not (bit == g.CHARGE_OVERDRIVE and already_over):
		charges &= ~bit
	g.streak_charges[peer_id] = charges
	push_streak(g, peer_id)
	g.streak_used.emit(peer_id, slot)
	if bit == g.CHARGE_RADAR:
		grant_radar(g, peer_id)


## UAV: every machine hears about it; the activator's team gets enemies on the minimap,
## the other team only the "enemy radar" cue. The minimap reads the live pawns, so
## enemies that respawn during the radar show up too. FFA: only the activator gets markers
## (of everyone else); all others get the "enemy radar" cue.
static func grant_radar(g: GameState, peer_id: int) -> void:
	var team := 0
	var p := g.player_for_peer(peer_id)
	if p:
		team = p.team_id
	elif g.scores.has(peer_id):
		team = int(g.scores[peer_id].get("team", 0))
	var by := g._display_name_for(peer_id)
	if g.scores.has(peer_id):
		by = str(g.scores[peer_id].name)
	if g.is_networked():
		g.sync_radar.rpc(team, by, g.RADAR_TIME, peer_id)
	apply_radar(g, team, by, g.RADAR_TIME, peer_id)
	if g._is_match_authority():
		UavDrone.launch(g, peer_id, team, g.RADAR_TIME) # the radar lives as long as the drone


## Every machine: a UAV of `team` (FFA: of `peer`) was shot down. Its radar ends now; another live
## friendly UAV keeps the radar for its own remaining time.
static func uav_down(g: GameState, team: int, peer: int) -> void:
	var mine := g.local_team()
	if mine < 0:
		return
	var friendly := (peer == g.multiplayer.get_unique_id()) if g.is_ffa() else team == mine
	if friendly and g.radar_left > 0.0:
		g.radar_left = UavDrone.team_remaining(team, peer, g.is_ffa())
		if g.radar_left <= 0.0:
			g.radar_team = -1
			g.radar_peer = 0


## Every machine: friendly UAV starts the minimap radar, an enemy one only shows the warning.
static func apply_radar(g: GameState, team: int, by_name: String, seconds: float, by_peer: int) -> void:
	var mine := g.local_team()
	if mine < 0:
		return
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	var friendly := team == mine
	if g.is_ffa():
		friendly = by_peer == g.multiplayer.get_unique_id()
	if friendly:
		g.radar_team = team
		g.radar_peer = by_peer
		g.radar_left = maxf(g.radar_left, seconds)
	if hud:
		hud.show_radar_event(by_name, team, friendly)


## Round end, round start, killcam, and leaving: no markers carry over, and no RC stays out.
static func clear_radar(g: GameState) -> void:
	g.radar_left = 0.0
	g.radar_team = -1
	g.radar_peer = 0
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.clear_radar()
	RcXd.abort_all()
	LosHands.abort_all()
	Overdrive.abort_all() # #388
	g.los_view = false
	UavDrone.clear_all()


## New round drops this life's kill count and any charge still held.
## Leave-to-menu clears the same dictionaries in reset_session. Without this, a radar
## banked last round is still usable after intermission. Clients hear it via sync_streak.
static func clear_round_streaks(g: GameState) -> void:
	var humans := {}
	for src in [g.streak_progress, g.streak_charges, g.streak_earned]:
		for id in src:
			if int(id) > 0:
				humans[int(id)] = true
	g.streak_progress.clear()
	g.streak_charges.clear()
	g.streak_earned.clear()
	var me := g.multiplayer.get_unique_id() if g.is_networked() else 1
	if me > 0:
		humans[me] = true
	for id in humans:
		push_streak(g, int(id))


## HUD calls Game.request_use_streak. Clients ask the server; clients cannot grant their own UAV.
static func request_use(g: GameState, slot: int) -> void:
	if g.is_networked() and not g.multiplayer.is_server():
		g.request_streak.rpc_id(1, slot)
	else:
		var id := g.multiplayer.get_unique_id() if g.is_networked() else 1
		g.try_activate_streak(id, slot)


## Server (rc_drive): only the car's owner steers it. No fallback to the local id: the host drives locally.
static func rc_drive(g: GameState, net_id: int, yaw_in: float, throttle_in: float) -> void:
	if not g.multiplayer.is_server():
		return
	var car := RcXd.authority_by_id(net_id)
	if car == null or car.owner_peer != g.multiplayer.get_remote_sender_id():
		return
	car.apply_remote_input(yaw_in, throttle_in)


## Server (rc_detonate): only the owner, and not while play is locked.
static func rc_detonate(g: GameState, net_id: int) -> void:
	if not g.multiplayer.is_server() or g.play_locked():
		return
	var car := RcXd.authority_by_id(net_id)
	if car == null or car.owner_peer != g.multiplayer.get_remote_sender_id():
		return
	car.shutdown(true)


## Client (sync_rc_pose): a late unreliable pose must not move a car that is already gone.
static func on_rc_pose(g: GameState, net_id: int, pos: Vector3, yaw_in: float, life_in: float, vel_in: Vector3) -> void:
	if g.multiplayer.is_server() or g._rc_done.has(net_id):
		return
	var car := RcXd.by_id(net_id)
	if car:
		car.apply_net_pose(pos, yaw_in, life_in, vel_in)


## Client (sync_rc_end): the car ends; with no copy here an explosion still plays its boom.
static func on_rc_end(g: GameState, net_id: int, pos: Vector3, exploded: bool) -> void:
	if g.multiplayer.is_server():
		return
	g._rc_done[net_id] = true
	var car := RcXd.by_id(net_id)
	if car:
		car.client_end(exploded, pos)
	elif exploded and not g.is_dedicated:
		Grenade.play_boom(pos, true)


static func on_rc_hp(g: GameState, net_id: int, value: float) -> void:
	if g.multiplayer.is_server():
		return
	var car := RcXd.by_id(net_id)
	if car:
		car.apply_hp(value)


## Same popup split as the radar: your team sees RC-XD, the other team sees ENEMY RC-XD.
static func announce_rc(g: GameState, peer_id: int, team: int) -> void:
	var by := g._display_name_for(peer_id)
	if g.scores.has(peer_id):
		by = str(g.scores[peer_id].name)
	if g.is_networked():
		g.sync_rc_announce.rpc(team, by, peer_id)
	show_rc_announce(g, team, by, peer_id)


## FFA: only the driver's own machine sees it as friendly.
static func show_rc_announce(g: GameState, team: int, by_name: String, by_peer: int) -> void:
	var mine := g.local_team()
	if mine < 0:
		return
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	if hud == null:
		return
	var friendly := team == mine
	if g.is_ffa():
		friendly = by_peer == g.multiplayer.get_unique_id()
	hud.show_rc_event(by_name, team, friendly)


## Authority: drone `d` reached 0 HP from `shooter_peer`. Kill feed, notice, early radar end everywhere.
static func uav_shot_down(g: GameState, d: UavDrone, shooter_peer: int, shooter_team: int, weapon_id: StringName) -> void:
	var shooter := g._display_name_for(shooter_peer)
	if g.scores.has(shooter_peer):
		shooter = str(g.scores[shooter_peer].name)
	g._emit_kill_feed(shooter, "UAV", weapon_id, shooter_team, d.team, "")
	if g.is_networked():
		g.sync_kill_feed.rpc(shooter, "UAV", String(weapon_id), shooter_team, d.team, "")
		g.sync_uav_end.rpc(d.net_id, d.team, d.owner_peer, shooter_peer)
	uav_end(g, d.net_id, d.team, d.owner_peer, shooter_peer)


## Every machine: the drone falls, the radar stops early, and the shooter gets the notice.
static func uav_end(g: GameState, id: int, team: int, owner_peer: int, shooter_peer: int) -> void:
	var d := UavDrone.by_id(id)
	if d:
		d.shoot_down()
	uav_down(g, team, owner_peer)
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	if hud and shooter_peer == g.multiplayer.get_unique_id():
		hud.show_notice("UAV neergeschoten", 2.5)
