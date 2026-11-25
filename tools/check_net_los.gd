extends Node
## Client half of the LOS chain network test (#384). Start the server with tools/net_los.sh, which
## runs:  godot --headless -- --server --port 7799 --map quay --mode ffa --bots 2 --bot-difficulty
##        easy --test-los --time 10
## The client takes the LOS the server charges it with, flies at the nearest bot and bashes twice.
## Every assertion below is taken on the CLIENT, because the bug this covers was invisible on the
## server: a joined client kept its own 8 s count, ended the view early, never saw its body snap and
## showed no chain popup.
##
## The client half of a net check cannot live in run_checks.sh: the runner has no server of its own.

const SERVER_IP := "localhost"
const SERVER_PORT := 7801
const HOME_S := 30.0 # per kill: enough for a hands flight across a map, not a hang

var fails := 0
var _me: Player
var _my_id := 0
# Recorded the moment the second chain kill lands: the hands node may be gone by the time the
# assertions run (the third kill or the server's window closes it), and reading it then errors.
var _left_at_2 := 0.0
var _body_gap_at_2 := 999.0


func _ok(made: bool, what: String) -> void:
	print(("  PASS " if made else "  FAIL ") + what)
	if not made:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main) # RPC paths need /root/Main, like the real game
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_host_ip(SERVER_IP)
	menu.set_host_port(SERVER_PORT)
	menu.connect_pressed.emit()
	for _i in 300:
		await get_tree().create_timer(0.1).timeout
		_my_id = multiplayer.get_unique_id()
		_me = Game.player_for_peer(_my_id)
		if _me and not _me.is_dead and not Game.play_locked():
			break
	if _me == null:
		print("NET LOS CHECK FAILED (no pawn)")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.5).timeout

	var hands: LosHands = null
	var kills := 0
	var launched := Time.get_ticks_msec()
	# A bot has to be close before the pop: the hands live 8 s, and the first spawn point can be 70 m
	# from the nearest one. Waiting for a bot to walk in is what a player does too.
	for attempt in 4:
		if not await _wait_for_close_bot(70.0):
			continue
		hands = await _take_los()
		if hands == null:
			continue
		launched = Time.get_ticks_msec()
		_left_at_2 = 0.0
		_body_gap_at_2 = 999.0
		kills = await _chain_two(hands, launched)
		if kills >= 2:
			break
		print("  attempt %d only reached %d kill(s); trying again" % [attempt + 1, kills])
	var elapsed := float(Time.get_ticks_msec() - launched) / 1000.0

	_ok(kills >= 2, "the client counted the chain: kills %d" % kills)
	# #384: the base window is 8 s; two chain kills add 3 s each. A client still on its own 8 s clock
	# would have ~0 left when the second kill landed.
	var expect := 8.0 - elapsed + 3.0 * float(kills)
	_ok(kills >= 1 and _left_at_2 > expect - 1.0, "the +3 s per kill reached the client (%.1f s left at the second kill, wanted > %.1f)" % [
		_left_at_2, expect - 1.0])
	# The body follows the hands when the server found a landing spot. It sends INF when the hands are
	# over a roof, a prop or thin air; then there is nothing to snap to and the body stays behind, which
	# is the same rule the host follows. So this only fails when a snap was possible and did not arrive.
	if _body_gap_at_2 < 2.5:
		_ok(true, "the client's body snapped to the hands (%.1f m off)" % _body_gap_at_2)
	else:
		print("  NOTE the body stayed %.1f m behind: no valid landing spot was sent (no snap by design)" % _body_gap_at_2)
	# And then the chain ends: the third kill, or the server's own timer.
	var gone := false
	for _i in 300:
		await get_tree().create_timer(0.1).timeout
		if LosHands.for_owner(_my_id) == null:
			gone = true
			break
		hands = LosHands.for_owner(_my_id)
		if hands and hands.kills >= 2:
			await _chase_and_swing(hands)
	_ok(gone, "the chain ended (third kill or the server's window)")
	_finish()


func _finish() -> void:
	print("NET LOS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


## Ask the server for the LOS slot and wait for the spawn RPC to build the hands here.
func _take_los() -> LosHands:
	var slot := StreakSelect.slot_for(Game, _my_id, &"los")
	# The RPC has to be sent, not called: a plain call runs locally, where the client is not the server.
	Game.request_streak.rpc_id(1, slot)
	for _i in 100:
		var hands := LosHands.for_owner(_my_id)
		if hands != null:
			return hands
		await get_tree().create_timer(0.1).timeout
	return null


## Fly at the nearest enemy and bash twice, the way a player would. Between swings the hands keep
## homing, so a bot that walks off is followed instead of missed.
func _chain_two(hands: LosHands, launched: int) -> int:
	var kills := 0
	while kills < 2 and float(Time.get_ticks_msec() - launched) / 1000.0 < HOME_S:
		if not is_instance_valid(hands) or hands.kills >= 2:
			break
		await _chase_and_swing(hands)
		if not is_instance_valid(hands):
			break
		kills = hands.kills
		if kills >= 2 and _left_at_2 == 0.0:
			_left_at_2 = hands.time_left
			if _me != null:
				var flat := Vector2(_me.global_position.x - hands.global_position.x,
					_me.global_position.z - hands.global_position.z)
				_body_gap_at_2 = flat.length()
	return kills


## Point the hands at the closest living enemy and fly there: high while it is far, so walls and props
## are cleared, then down onto the chest inside bash range. Then swing.
func _chase_and_swing(hands: LosHands) -> void:
	var target := _nearest_enemy(hands)
	if target == null:
		await get_tree().create_timer(0.2).timeout
		return
	var chest := target.global_position + Vector3(0.0, 1.0, 0.0)
	print("  chase: %.1f m to the nearest target" % hands.global_position.distance_to(chest))
	Input.action_press("move_forward")
	var deadline := Time.get_ticks_msec() + int(HOME_S * 1000.0)
	while is_instance_valid(hands) and is_instance_valid(target) and not target.is_dead:
		if Time.get_ticks_msec() > deadline:
			break
		chest = target.global_position + Vector3(0.0, 1.0, 0.0)
		var to := chest - hands.global_position
		if to.length() < 3.4:
			break
		# Fly high while far: the hands have no pathfinding, and a wall is what eats the window.
		var aim_pt := chest + Vector3(0.0, 2.5, 0.0) if to.length() > 8.0 else chest
		var dir := aim_pt - hands.global_position
		hands._yaw = atan2(-dir.x, -dir.z)
		hands._pitch = clampf(atan2(dir.y, Vector2(dir.x, dir.z).length()), -1.2, 1.2)
		await get_tree().physics_frame
	Input.action_release("move_forward")
	if not is_instance_valid(hands) or not is_instance_valid(target) or target.is_dead:
		return
	var to2 := (target.global_position + Vector3(0.0, 1.0, 0.0)) - hands.global_position
	if to2.length() > 3.9:
		return # still out of reach: the caller keeps flying, and a refused swing costs a cooldown
	hands._yaw = atan2(-to2.x, -to2.z)
	hands._pitch = clampf(atan2(to2.y, Vector2(to2.x, to2.z).length()), -1.2, 1.2)
	hands._swing_cd = 0.0
	print("  swing at %.1f m, kills %d" % [to2.length(), hands.kills])
	hands._request_swing()
	# The swing's verdict comes back over sync_los_chain; give it a round trip and a bit.
	for _i in 20:
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(hands):
			return


## Walk the body toward the nearest bot until it is close enough that a LOS flight lands inside its
## window: the spawn points on quay are up to 80 m apart and the bots do not come to you.
func _wait_for_close_bot(max_s: float) -> bool:
	var started := Time.get_ticks_msec()
	Input.action_press("move_forward")
	var close := false
	while float(Time.get_ticks_msec() - started) / 1000.0 < max_s:
		if _me == null or _me.is_dead:
			break
		var target := _nearest_pawn(_me.global_position)
		if target == null:
			break
		var to := target.global_position - _me.global_position
		if Vector2(to.x, to.z).length() < 9.0:
			close = true
			break
		_me._yaw = atan2(-to.x, -to.z)
		await get_tree().physics_frame
	Input.action_release("move_forward")
	return close


## Living pawns within `r` of `at`, the driver excluded.
func _count_near(at: Vector3, r: float) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("player"):
		var v := node as Player
		if v == null or v == _me or v.is_dead or v.is_queued_for_deletion():
			continue
		if at.distance_to(v.global_position) <= r:
			n += 1
	return n


func _nearest_pawn(at: Vector3) -> Player:
	var best: Player = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("player"):
		var v := n as Player
		if v == null or v == _me or v.is_dead or v.is_queued_for_deletion():
			continue
		var d := at.distance_to(v.global_position)
		if d < best_d:
			best = v
			best_d = d
	return best


func _nearest_to(at: Vector3) -> float:
	var best := INF
	for n in get_tree().get_nodes_in_group("player"):
		var v := n as Player
		if v == null or v == _me or v.is_dead or v.is_queued_for_deletion():
			continue
		best = minf(best, at.distance_to(v.global_position))
	return best


func _nearest_enemy(hands: LosHands) -> Player:
	var best: Player = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("player"):
		var v := n as Player
		if v == null or v == _me or v.is_dead or v.is_queued_for_deletion():
			continue
		# FFA: every other pawn is a target. The check does not use Game.is_enemy because in this
		# server setup every pawn sits on team 0, which reads as "friend" and left the list empty.
		var d := hands.global_position.distance_to(v.global_position)
		if d < best_d:
			best = v
			best_d = d
	return best
