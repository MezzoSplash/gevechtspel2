extends Node
## #252 regression: the reload style a remote pawn plays is resolved from the index that travels with
## `sync_reload`, and that index has to be an ARMORY index.
##   godot --headless --path . res://tools/check_reload_style_sync.tscn   → "RELOAD STYLE SYNC CHECK OK"
##
## The bug this guards: the sender used `_active_index` (the slot in the shooter's `slots`, i.e. only
## their class's two guns) while the receiver read it as an index into `Weapon.LOADOUT` (the whole
## armory). A Breacher's shotgun is slot 0 but armory 2, so every other client played the rifle's `mag`
## reload on a shotgun. Nothing failed: it was a plausible index that pointed at a different gun.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _pawn(id: int) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = id
	p.set_physics_process(false)
	add_child(p) # _ready builds the weapon's view models and its slots
	return p


func _ready() -> void:
	# 1) The armory index is the index the receiver uses; every gun in the armory round-trips.
	for i in Weapon.LOADOUT.size():
		var gun := Weapon.LOADOUT[i]
		_ok(Weapon.style_for_reload_index(i) == gun.reload_style,
			"armory %d (%s) resolves to its own style '%s'" % [i, gun.id, gun.reload_style])
	_ok(Weapon.style_for_reload_index(-1) == &"" and Weapon.style_for_reload_index(Weapon.LOADOUT.size()) == &"",
		"an index outside the armory resolves to nothing, so the receiver can fall back")

	# 2) Every default class, every slot: what the shooter puts on the wire has to name the gun held.
	var receiver := _pawn(11) # a remote copy: full armory, no class
	var covered_mismatch := false
	for c in PlayerClasses.DEFAULTS:
		var shooter := _pawn(1) # the owner: a class loadout of two guns
		shooter.weapon.set_slots([c["primary"], c["secondary"]])
		for slot in shooter.weapon.slots.size():
			# Public switch path: equip_remote goes by id and keeps `_active_index` in step with slots.
			shooter.weapon.equip_remote(shooter.weapon.slots[slot].id)
			var held: WeaponDef = shooter.weapon.def
			var wire: int = shooter.weapon.reload_wire_index()
			var slot_index: int = shooter.weapon.active_index()
			_ok(Weapon.LOADOUT[wire].id == held.id,
				"%s slot %d (%s) goes on the wire as armory %d" % [c["name"], slot, held.id, wire])
			if slot_index != wire:
				covered_mismatch = true
			# The receiver's half of the contract, through the real entry point.
			receiver.weapon.play_remote_reload(wire, 1.0)
			_ok(receiver.weapon.reload_style_now() == held.reload_style,
				"%s slot %d: the remote body plays '%s', not another gun's style"
					% [c["name"], slot, held.reload_style])
		shooter.queue_free()
	_ok(covered_mismatch,
		"at least one class has slot index != armory index (otherwise this check proves nothing)")

	# 3) The bug itself: the old sender value points at a different gun. If this ever stops being true the
	# check above has lost its teeth and needs a new precondition.
	var breacher := _pawn(1)
	breacher.weapon.set_slots(["shotgun", "pistol"])
	_ok(Weapon.LOADOUT[breacher.weapon.active_index()].id != breacher.weapon.def.id,
		"a Breacher's slot 0 is not LOADOUT[0] (the slot index is not an armory index)")
	_ok(breacher.weapon.reload_wire_index() == Weapon.LOADOUT.find(breacher.weapon.def),
		"reload_wire_index() is the held gun's armory index")
	breacher.queue_free()

	# 4) A reload that ends (time 0) clears the remote timer, as before.
	receiver.weapon.play_remote_reload(0, 1.0)
	receiver.weapon.play_remote_reload(0, 0.0)
	_ok(receiver.weapon.reload_anim() == 0.0, "a zero-length sync stops the remote reload")

	# 5) A gun outside the armory: the sender cannot name it, so the receiver has to fall back to the gun
	# the pawn holds. This is the -1 the review asked about; without it that fallback was dead code.
	var ghost := WeaponDef.new()
	ghost.id = &"ghost_gun"
	ghost.reload_style = &"bolt" # deliberately unlike the rifle (mag), so the fallback cannot pass by luck
	receiver.weapon.def = ghost
	_ok(receiver.weapon.reload_wire_index() == -1, "a gun outside the armory has no wire index (-1)")
	_ok(receiver.weapon.armory_index() == 0, "the killcam's armory_index() stays usable (0), never -1")
	receiver.weapon.play_remote_reload(receiver.weapon.reload_wire_index(), 1.0)
	_ok(receiver.weapon.reload_style_now() == &"bolt",
		"an unknown index falls back to the held gun's own style (%s)" % receiver.weapon.reload_style_now())
	receiver.weapon.def = Weapon.LOADOUT[0]

	# 6) The senders themselves. The number only exists on the wire, so this half reads the source, the
	# same way check_rpc_channels guards the channel annotations: a runtime test cannot see what a sender
	# hands to Game.notify_reload, and passing the slot index there is exactly the bug. All three call
	# sites count: _start_reload, _cancel_reload (a reload that ends early) and refill (a fresh magazine).
	var src := FileAccess.get_file_as_string("res://scripts/weapon.gd")
	var sends := 0
	var wire := 0
	for line in src.split("\n"):
		if line.contains("Game.notify_reload("):
			sends += 1
			if line.contains("reload_wire_index()"):
				wire += 1
	_ok(sends == 3, "weapon.gd has three reload senders (%d)" % sends)
	_ok(wire == sends, "every sender puts the armory index on the wire (%d of %d)" % [wire, sends])
	_ok(not src.contains("notify_reload(owner as Player, _active_index"),
		"no sender passes its slot index to Game.notify_reload")

	print("RELOAD STYLE SYNC CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
