class_name LaunchArgs
extends RefCounted
## Command line after `--` (#106): --server, --port, --connect host[:port], --name, --map, --mode, --kills,
## --style, --time, --bots, --bot-difficulty. Unknown values print a hint and keep the default.


static func parse(args: PackedStringArray) -> Dictionary:
	var out := {"server": false, "port": Game.DEFAULT_PORT, "connect": "", "name": "", "map": &"", "mode": -1, "kills": -1, "style": -1, "time_min": -1, "bots": -1, "bot_difficulty": -1}
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--server":
				out.server = true
			"--port":
				i += 1
				if i < args.size():
					out.port = int(args[i])
			"--connect":
				i += 1
				if i < args.size():
					var raw := args[i]
					if raw.contains(":"):
						var parts := raw.split(":")
						out.connect = parts[0]
						out.port = int(parts[1])
					else:
						out.connect = raw
			"--name":
				i += 1
				if i < args.size():
					out.name = args[i]
			"--map":
				i += 1
				if i < args.size():
					out.map = Maps.parse(args[i])
					if out.map == &"":
						printerr("Unknown --map '%s'. Maps: %s" % [args[i], ", ".join(Maps.ORDER)])
			"--mode":
				i += 1
				if i < args.size():
					out.mode = Game.parse_mode(args[i])
					if out.mode < 0:
						printerr("Unknown --mode '%s'. Use tdm, ffa, style-tdm or style-ffa." % args[i])
			"--kills":
				i += 1
				if i < args.size():
					out.kills = int(args[i])
			"--style":
				i += 1
				if i < args.size():
					out.style = int(args[i])
			"--time":
				i += 1
				if i < args.size():
					out.time_min = int(args[i])
			"--bots":
				i += 1
				if i < args.size():
					out.bots = int(args[i])
			"--bot-difficulty":
				i += 1
				if i < args.size():
					out.bot_difficulty = Game.parse_bot_difficulty(args[i])
					if out.bot_difficulty < 0:
						push_warning("--bot-difficulty: use easy, medium or hard (got %s)" % args[i])
		i += 1
	return out
