class_name Loadouts
extends Node
## Child of Game (`Game.loadouts`). Two halves:
## - local: your saved classes (user://classes.cfg) and which one you picked this session;
## - server: each human's validated loadout. The first pick of a session applies at once (you are
##   standing in spawn); every later pick waits in `_pending` until that pawn's next spawn.
## Bots keep their old fixed gun and full armory (empty loadout = armory, see Player.weapon_ids).

signal classes_changed
signal loadout_applied(loadout: Dictionary, now: bool) # local pawn got a server-confirmed loadout

var classes: Array[Dictionary] = []
var last_index := 0
var picked_once := false # this session: the start-of-match pick happened (or auto-assigned)
var queued_index := -1 # local: picked mid-match, waiting for the next spawn
var mine: Dictionary = {} # local: last loadout the server confirmed for our pawn
var save_path := PlayerClasses.SAVE_PATH

var _current: Dictionary = {} # server: peer_id → loadout in use
var _pending: Dictionary = {} # server: peer_id → loadout for the next spawn
var _chosen: Dictionary = {} # server: peer_id → true after the first pick


func _ready() -> void:
	name = "Loadouts" # same node path on every peer, the RPCs need it
	reload()


func reload() -> void:
	var data := PlayerClasses.load_file(save_path)
	classes = data.classes
	last_index = int(data.last)
	classes_changed.emit()


func save() -> void:
	PlayerClasses.save_file(classes, last_index, save_path)
	classes_changed.emit()


func can_add() -> bool:
	return classes.size() < PlayerClasses.MAX_CLASSES


## New class copies the defaults' first entry with a free "Class N" name. Returns its index or -1.
func add_class() -> int:
	if not can_add():
		return -1
	var n := classes.size() + 1
	var taken := {}
	for c in classes:
		taken[c.name] = true
	while taken.has("Class %d" % n):
		n += 1
	var c := PlayerClasses.sanitize_class(PlayerClasses.DEFAULTS[0])
	c.name = "Class %d" % n
	classes.append(c)
	save()
	return classes.size() - 1


## The last class cannot go: the selection screen always needs something to auto-assign.
func delete_class(i: int) -> bool:
	if classes.size() <= 1 or i < 0 or i >= classes.size():
		return false
	classes.remove_at(i)
	if last_index == i:
		last_index = 0
	elif last_index > i:
		last_index -= 1
	if queued_index == i:
		queued_index = -1
	elif queued_index > i:
		queued_index -= 1
	save()
	return true


func update_class(i: int, c: Dictionary) -> void:
	if i < 0 or i >= classes.size():
		return
	classes[i] = PlayerClasses.sanitize_class(c, classes[i].name)
	save()


func auto_index() -> int:
	return clampi(last_index, 0, classes.size() - 1)


## Local pick. The server decides whether it applies now (first pick) or at the next spawn.
## Returns true when it will wait for the next spawn (the caller shows the notice).
func choose(i: int) -> bool:
	if classes.is_empty():
		return false
	i = clampi(i, 0, classes.size() - 1)
	var first := not picked_once
	picked_once = true
	last_index = i
	save()
	queued_index = -1 if first else i
	var l := PlayerClasses.to_loadout(classes[i])
	if Game.is_networked() and not multiplayer.is_server():
		request_loadout.rpc_id(1, l)
	else:
		server_submit(multiplayer.get_unique_id(), l)
	return not first


func class_name_at(i: int) -> String:
	return str(classes[i].name) if i >= 0 and i < classes.size() else ""


# --- server -------------------------------------------------------------------------------------


@rpc("any_peer", "reliable")
func request_loadout(raw: Variant) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer <= 0:
		return
	server_submit(peer, raw)


## Authority only. Invalid loadouts are dropped and the old one stays. Returns true if accepted.
func server_submit(peer: int, raw: Variant) -> bool:
	var l := PlayerClasses.parse_loadout(raw)
	if l.is_empty():
		print("SERVER: rejected loadout from %d: %s" % [peer, str(raw)])
		return false
	var p := Game.player_for_peer(peer)
	var first := not _chosen.has(peer)
	_chosen[peer] = true
	if p == null:
		_current[peer] = l # no pawn yet: it spawns with this
		_pending.erase(peer)
		return true
	if first and not p.is_dead:
		_current[peer] = l
		_pending.erase(peer)
		_apply(p, l, true)
		return true
	_pending[peer] = l
	return true


## For a human pawn being built on the authority.
func spawn_loadout(peer: int) -> Dictionary:
	if _current.has(peer):
		return (_current[peer] as Dictionary).duplicate(true)
	return PlayerClasses.default_loadout()


func pending_for(peer: int) -> Dictionary:
	return _pending.get(peer, {})


## Authority, right before a respawn is broadcast: the waiting class becomes the active one.
## The owner hears it first (same reliable channel as broadcast_respawn), so its pawn spawns with it.
func promote_pending(p: Player) -> void:
	if p == null or p.is_bot or not _pending.has(p.peer_id):
		return
	var l: Dictionary = _pending[p.peer_id]
	_pending.erase(p.peer_id)
	_current[p.peer_id] = l
	_apply(p, l, false)


## now=true: equip right away (first pick). now=false: stored, used by the coming respawn.
func _apply(p: Player, l: Dictionary, now: bool) -> void:
	p.loadout = l.duplicate(true)
	if now:
		p.apply_loadout()
	if p.is_local():
		mine = l.duplicate(true)
		if not now:
			queued_index = -1
		loadout_applied.emit(l, now)
	elif Game.is_networked():
		sync_loadout.rpc_id(p.peer_id, l, now)
	if now and Game.is_networked():
		Game.sync_weapon.rpc(p.peer_id, String(p.loadout.primary))


@rpc("authority", "reliable")
func sync_loadout(l: Dictionary, now: bool) -> void:
	if multiplayer.is_server():
		return
	mine = l.duplicate(true)
	if not now:
		queued_index = -1
	var p := Game.player_for_peer(multiplayer.get_unique_id())
	if p:
		p.loadout = l.duplicate(true)
		if now:
			p.apply_loadout()
	loadout_applied.emit(l, now)


func forget(peer: int) -> void:
	_current.erase(peer)
	_pending.erase(peer)
	_chosen.erase(peer)


## Leave to menu. Saved classes stay; the session's picks go.
func reset() -> void:
	_current.clear()
	_pending.clear()
	_chosen.clear()
	mine.clear()
	picked_once = false
	queued_index = -1
