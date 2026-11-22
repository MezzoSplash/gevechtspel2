class_name NetStats
extends RefCounted
## #364: the network line in the HUD (Settings > HUD > Network stats). Everything here comes from
## ENet's own peer statistics, because Godot 4.7 exposes nothing else: there is no
## `Performance.NETWORK_IN`/`NETWORK_OUT` and an `ENetPacketPeer` has no byte or packet counters, so
## this is latency and loss, not bandwidth. A number we do not have prints as "—" and never as a zero
## that looks healthy.
##
## Client: peer 1 is the server. Server: its own row is 0 ms ("host") and the worst peer wins the
## numbers, so a host sees the worst connection in the match instead of an average that hides one
## player on a bad line. Bots are not peers: they get their own count.

const NA := "—"


## The overlay line. Pure, so a headless check can print every case: host, a client with real
## numbers, offline, and a measurement ENet has not made yet. `loss` is the ratio ENet returns
## (PACKET_LOSS_SCALE = 65536 of them make 100%), `jitter` and `rtt` are in ms, `bots` is only shown
## when there are any.
static func line_of(networked: bool, host: bool, rtt_ms: int, loss: float, jitter_ms: float,
		peers: int, bots: int, interp_ms: int) -> String:
	if not networked:
		return "net  offline"
	var rtt := "host" if host and rtt_ms == 0 else (NA if rtt_ms < 0 else "%d ms" % rtt_ms)
	var lost := NA if loss < 0.0 else "%.1f%%" % (loss * 100.0)
	var jitter := NA if jitter_ms < 0.0 else "%.1f ms" % jitter_ms
	var out := "net  rtt %s   loss %s   jitter %s   peers %d" % [rtt, lost, jitter, peers]
	if bots > 0:
		out += "   bots %d" % bots
	return out + "   interp %d ms" % interp_ms


## ENet's view of this process's connections, as a Dictionary so the caller never touches a peer
## that has gone away between the read and the format. `interp_ms` is passed in rather than read from
## LagComp here: a headless `-s` check preloads this script, and a class it drags in at compile time
## would pull the autoloads into a run that has no scene tree.
static func read(game, interp_ms: int = 150) -> Dictionary:
	var out := {
		"networked": false, "host": false, "rtt": -1, "loss": -1.0, "jitter": -1.0,
		"peers": 0, "bots": 0, "interp": interp_ms,
	}
	if game == null or not game.is_inside_tree():
		return out
	out["networked"] = game.is_networked()
	out["host"] = game.multiplayer.is_server()
	# Bots are negative peer ids in the score table (MatchFlow.sample_pings reads them the same way).
	for id in game.scores:
		if int(id) < 0:
			out["bots"] = int(out["bots"]) + 1
	if not out["networked"]:
		return out
	var ids: Array = game.multiplayer.get_peers()
	out["peers"] = ids.size()
	if out["host"]:
		out["rtt"] = 0 # the server has no peer entry for itself; "host" is the honest reading
	var enet := game.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return out
	# A client measures the server (peer 1); a server measures every client and keeps the worst.
	var targets: Array = ids if out["host"] else ([1] if ids.is_empty() == false else [])
	for id in targets:
		var ep := enet.get_peer(int(id))
		if ep == null or not ep.is_active():
			continue
		out["rtt"] = maxi(int(out["rtt"]), int(ep.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)))
		out["loss"] = maxf(float(out["loss"]),
			float(ep.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)) / float(ENetPacketPeer.PACKET_LOSS_SCALE))
		out["jitter"] = maxf(float(out["jitter"]),
			float(ep.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)))
	return out


## The line for `game`, ready for the HUD.
static func text(game, interp_ms: int = 150) -> String:
	var d := read(game, interp_ms)
	return line_of(bool(d["networked"]), bool(d["host"]), int(d["rtt"]), float(d["loss"]),
		float(d["jitter"]), int(d["peers"]), int(d["bots"]), int(d["interp"]))
