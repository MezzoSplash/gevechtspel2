extends SceneTree
## #139: the ENet channel every @rpc uses, read from the source as text.
##   godot --headless --path . -s res://tools/check_rpc_channels.gd   → "RPC CHANNEL CHECK OK"
##
## Why a text check: a channel is an annotation, so nothing at runtime can show which one a function
## ended up on. The risk this guards is silent drift — one new @rpc without a channel puts a gameplay
## message back behind the HUD queue, which only shows up as lag on a lossy connection.
##
## Channel 1 = gameplay (fire, switch, damage, knockback, position, streak input, LOS input).
## Channel 2 = cosmetic (kill feed, combo, trick, tracers, pings, radar, voices, chat, round clock).
## Channel 0 (default) = state/setup (match config, lobby, roster, spawn, scores, round end, flags):
## those must keep their order relative to each other, so they stay on one channel together.

const SRC := "res://shared/game.gd"

const GAMEPLAY: Array[String] = [
	"request_weapon_fire", "request_weapon_switch", "request_grenade", "request_knife",
	"notify_hit", "broadcast_hurt", "sync_knockback", "correct_position", "sync_weapon", "sync_regen",
	"sync_los_spawn", "sync_los_pose", "sync_los_end", "los_input", "los_melee", "los_recall",
	"request_streak", "rc_drive", "rc_detonate", "sync_rc_kick", "sync_rc_spawn", "sync_rc_pose",
	"sync_rc_end", "sync_rc_hp", "sync_grenade_spawn", "sync_grenade_pose", "sync_grenade_boom",
	"sync_knife_spawn",
]
const COSMETIC: Array[String] = [
	"sync_kill_feed", "sync_trick", "sync_combo", "sync_shot_fx", "sync_pings", "sync_radar",
	"sync_rc_announce", "sync_uav_spawn", "sync_uav_end", "sync_round_time", "sync_bot_poses",
	"broadcast_chat", "submit_chat", "sync_death_report",
]
const MIN_GAMEPLAY := 20 # a sane floor: an annotation stripped in bulk must not pass


func _initialize() -> void:
	quit(1 if _run() > 0 else 0)


func _run() -> int:
	var text := FileAccess.get_file_as_string(SRC)
	if text.is_empty():
		print("  FAIL cannot read %s" % SRC)
		print("RPC CHANNEL CHECK FAILED")
		return 1
	# @rpc("authority", "reliable", 2) followed by optional ## doc lines. A channel is the last
	# integer argument; no integer means the default channel 0.
	var re := RegEx.new()
	re.compile("@rpc\\(([^)\\n]*)\\)(?:\\n(?:#[^\\n]*\\n)*)?func ([a-z_0-9]+)\\(")
	var seen := {}
	for m in re.search_all(text):
		var args := m.get_string(1)
		var name := m.get_string(2)
		var chan := 0
		var chan_re := RegEx.new()
		chan_re.compile(",\\s*([0-9]+)\\s*$")
		var cm := chan_re.search(args.strip_edges())
		if cm:
			chan = int(cm.get_string(1))
		seen[name] = chan
	var fails := 0
	for name in GAMEPLAY:
		fails += _ok(seen.get(name, -1) == 1, "%s on channel 1 (gameplay)" % name, seen.get(name, -1))
	for name in COSMETIC:
		fails += _ok(seen.get(name, -1) == 2, "%s on channel 2 (cosmetic)" % name, seen.get(name, -1))
	var gameplay_seen := 0
	for name in seen:
		if not (name in GAMEPLAY) and not (name in COSMETIC):
			fails += _ok(int(seen[name]) == 0, "%s stays on channel 0 (state)" % name, int(seen[name]))
		if name in GAMEPLAY and int(seen[name]) == 1:
			gameplay_seen += 1
	fails += _ok(gameplay_seen >= MIN_GAMEPLAY, "at least %d gameplay RPCs on channel 1 (%d)" % [
		MIN_GAMEPLAY, gameplay_seen], gameplay_seen)
	print("RPC CHANNEL CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	return fails


func _ok(cond: bool, msg: String, got: int) -> int:
	if cond:
		print("  PASS %s" % msg)
		return 0
	print("  FAIL %s (got channel %d)" % [msg, got])
	return 1
