extends Node
## The weapon lab (docs/art/wapens.md): a quiet Townhouses with no bots where you hold every gun, so an
## artist sees a new model, flash, clip or sound in the game itself. Open this scene in the editor and
## press F6 (Run Current Scene), or: ./run.sh res://tools/weapon_lab.tscn
##   1-9 / Q   pick a gun          LMB  shoot          R  reload          F  throw the knife
##   L         read every gun's files again (after you saved a change), and check them
## What is wrong with a kit (WeaponKit.problems) is shown on screen.
## `-- --shot DIR` fires each gun once, saves DIR/lab-<id>.png and quits (xvfb, not in CI).
var me: Player
var label: Label
var main: Node


func _ready() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 0
	Game.bot_count = 0
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null and Game._round_active:
			break
	if me == null:
		push_error("weapon lab: no local pawn")
		return
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_arm()
	label = Label.new()
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_left = -600.0 # the right edge: the game's own left column stays readable
	label.offset_top = 80.0
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(label)
	add_child(layer)
	_refresh()
	var args := OS.get_cmdline_user_args()
	var at := args.find("--shot")
	if at >= 0 and at + 1 < args.size():
		await _shoot_all(args[at + 1])


## Every gun: draw it, fire one round mid-flash, save a picture.
func _shoot_all(dir: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in Weapon.LOADOUT.size():
		var def := Weapon.LOADOUT[i] as WeaponDef
		me.weapon._equip(i)
		_refresh()
		await get_tree().create_timer(0.4).timeout
		if not def.melee:
			me.weapon._cooldown = 0.0
			me.weapon._fire()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/lab-%s.png" % [dir, def.id])
	print("WEAPON LAB: shots in %s" % dir)
	get_tree().quit(0)


## Every gun in the slots, full ammo, knives, and no way to die.
func _arm() -> void:
	var ids: Array = []
	for d in Weapon.LOADOUT:
		ids.append((d as WeaponDef).id)
	me.weapon.set_slots(ids)
	me.weapon.refill()
	me.knives = 3
	me._spawn_protect = 1.0e9


func _unhandled_input(event: InputEvent) -> void:
	if me == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_5 and key <= KEY_9: # 1-4 are the game's own keys
		me.weapon._equip(key - KEY_1)
	elif key == KEY_L:
		WeaponKit.clear_cache()
		me.weapon.rebuild_view_models()
	if me.knives < 1:
		me.knives = 3
	_refresh.call_deferred()


func _process(_delta: float) -> void:
	if me != null and is_instance_valid(me):
		me._spawn_protect = 1.0e9 # the lab only keeps you alive; reloading is the game's own
	Game._round_timer = 0.0 # and the round never runs out


func _refresh() -> void:
	if label == null or me == null:
		return
	var lines: Array[String] = ["WEAPON LAB", "1-9/Q wapen · LMB schieten · R herladen", "F mes · L bestanden opnieuw inlezen", ""]
	for i in Weapon.LOADOUT.size():
		var id: StringName = (Weapon.LOADOUT[i] as WeaponDef).id
		var held: bool = me.weapon.def != null and me.weapon.def.id == id
		var src := WeaponKit.scene_path(id).trim_prefix("res://assets/weapons/")
		var kit := "map" if WeaponKit.has_folder(id) else "oud"
		lines.append("%s %d  %-9s %-4s %s" % ["▶" if held else " ", i + 1, id, kit, src])
	for id in WeaponKit.folders():
		for p in WeaponKit.problems(id):
			lines.append("⚠ %s: %s" % [id, p])
	label.text = "\n".join(lines)
