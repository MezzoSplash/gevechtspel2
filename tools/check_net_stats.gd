extends SceneTree
## Headless checks for the network line in the HUD (#364): shared/net_stats.gd.
##
##   godot --headless res://tools/check_net_stats.gd   (or ./tools/run_checks.sh check_net_stats)
##
## Only the pure formatter is exercised, so this check needs no autoloads and no live match: every
## case is a set of numbers ENet could hand us, including the ones it has not measured yet.

const NetStatsScript := preload("res://shared/net_stats.gd")

var _fails: Array[String] = []
var _passes := 0


func _initialize() -> void:
	var n := _run()
	quit(1 if n > 0 else 0)


func _run() -> int:
	# Offline: singleplayer has no peer at all, so the line says so instead of showing zeroes.
	_ok(NetStatsScript.line_of(false, false, -1, -1.0, -1.0, 0, 0, 150) == "net  offline",
		"offline prints net  offline")

	# Host: its own row is 0 ms and reads as "host", not as a suspiciously perfect ping.
	var host: String = NetStatsScript.line_of(true, true, 0, 0.0, 0.0, 2, 0, 150)
	_ok(host.contains("rtt host"), "host reads rtt host (%s)" % host)
	_ok(host.contains("loss 0.0%"), "host reads a real 0%% loss (%s)" % host)
	_ok(host.contains("peers 2"), "host counts its two peers (%s)" % host)
	_ok(not host.contains("bots"), "no bot count when there are no bots (%s)" % host)

	# Client: rtt/jitter in ms, loss as the ratio ENet returns (PACKET_LOSS_SCALE = 65536 of them
	# make 100%), and the bot count only when bots are in the match.
	var client: String = NetStatsScript.line_of(true, false, 42, 0.004, 1.1, 1, 12, 150)
	_ok(client.contains("rtt 42 ms"), "client rtt in ms (%s)" % client)
	_ok(client.contains("loss 0.4%"), "1/250 of the loss scale reads as 0.4%% (%s)" % client)
	_ok(client.contains("jitter 1.1 ms"), "jitter in ms (%s)" % client)
	_ok(client.contains("peers 1"), "a client counts the server as one peer (%s)" % client)
	_ok(client.contains("bots 12"), "bot count is shown when bots play (%s)" % client)
	_ok(client.contains("interp 150 ms"), "the interpolation delay is named (%s)" % client)

	# Full loss, at the scale's own unit: a value ENet reports as 65536 has to read 100.0%.
	_ok(NetStatsScript.line_of(true, false, 9, 1.0, 0.0, 1, 0, 150).contains("loss 100.0%"),
		"the loss scale is divided once, so 1.0 reads 100.0%")

	# Not measured yet: ENet reports nothing until it has packets, and that is not "0 ms, 0%".
	var unknown: String = NetStatsScript.line_of(true, false, -1, -1.0, -1.0, 1, 0, 150)
	_ok(unknown.contains("rtt %s" % NetStatsScript.NA), "a missing rtt prints a dash (%s)" % unknown)
	_ok(unknown.contains("loss %s" % NetStatsScript.NA), "a missing loss prints a dash (%s)" % unknown)
	_ok(unknown.contains("jitter %s" % NetStatsScript.NA), "a missing jitter prints a dash (%s)" % unknown)

	if _fails.is_empty():
		print("NET STATS CHECK: OK (%d assertions)" % _passes)
	else:
		print("NET STATS CHECK: FAIL (%d of %d)" % [_fails.size(), _passes + _fails.size()])
		for f in _fails:
			print("FAILED: %s" % f)
	return _fails.size()


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS %s" % msg)
	else:
		_fails.append(msg)
