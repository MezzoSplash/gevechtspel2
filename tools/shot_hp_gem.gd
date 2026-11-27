extends Node
## #319: renders the HUD with the HP gem at full, half and low HP (and with armour), so a human can judge
## the shard, the two seams and the red pulse.
##   xvfb-run -a godot --path . res://tools/shot_hp_gem.tscn -- --out /tmp
var out := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and me.weapon != null and not Game.play_locked() and Game._round_active:
			break
	if me == null:
		print("SHOT HP GEM: no round")
		get_tree().quit(1)
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	# De match zet HP elke tick opnieuw; voor de screenshot zetten we de beweging van de pop uit en
	# schrijven we de HP zelf, zodat de gem de stand toont die we willen laten zien.
	me.set_physics_process(false)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		print("SHOT HP GEM: no hud")
		get_tree().quit(1)
		return
	# De HUD leest HP via zijn eigen signaal/aanroep; _on_health is dezelfde weg als in een match.
	await _shot(hud, 100.0, 0.0, "%s/hp_gem_full.png" % out)
	await _shot(hud, 55.0, Pickups.ARMOUR * 0.6, "%s/hp_gem_half.png" % out)
	await _shot(hud, 18.0, 0.0, "%s/hp_gem_low.png" % out)
	print("SHOT HP GEM: done")
	get_tree().quit()


func _shot(hud: Node, hp: float, armour: float, path: String) -> void:
	var me: Player = Game.player_for_peer(multiplayer.get_unique_id())
	if me != null:
		# De match blijft HP bijwerken (regen, sync); voor de shot koppelen we die twee signalen los en
		# zetten we de stand zelf, zodat de gem toont wat we willen laten zien.
		var on_hp := Callable(hud, "_on_health")
		var on_ar := Callable(hud, "_on_armour")
		if me.health_changed.is_connected(on_hp):
			me.health_changed.disconnect(on_hp)
		if me.armour_changed.is_connected(on_ar):
			me.armour_changed.disconnect(on_ar)
		me.hp = hp
		me.armour = armour
	hud.call("_on_armour", armour)
	hud.call("_on_health", hp, Player.MAX_HP)
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())
