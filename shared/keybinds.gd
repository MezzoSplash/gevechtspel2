class_name Keybinds
extends RefCounted
## Key and mouse bindings (#106): defaults, saved codes, rebinding, labels. Static helpers on the Game
## autoload `g`; Game keeps the wrappers under the old names.


static func bind_inputs(g: GameState) -> void:
	key(g, "move_forward", KEY_W)
	key(g, "move_back", KEY_S)
	key(g, "move_left", KEY_A)
	key(g, "move_right", KEY_D)
	key(g, "jump", KEY_SPACE)
	key(g, "reload", KEY_R)
	key(g, "switch_weapon", KEY_Q)
	key(g, "weapon_1", KEY_1)
	key(g, "weapon_2", KEY_2)
	key(g, "weapon_3", KEY_3)
	key(g, "weapon_4", KEY_4)
	key(g, "use_streak", KEY_ENTER) # not ui_accept: that one includes Space (jump)
	key(g, "use_streak", KEY_KP_ENTER)
	mouse(g, "fire", MOUSE_BUTTON_LEFT)
	mouse(g, "zoom", MOUSE_BUTTON_RIGHT)
	key(g, "toggle_mouse", KEY_ESCAPE)
	key(g, "chat", KEY_T)
	key(g, "grenade", KEY_G)
	key(g, "throw_knife", KEY_F)
	key(g, "melee", KEY_E)
	key(g, "sprint", KEY_SHIFT)
	key(g, "crouch", KEY_CTRL)
	key(g, "crouch", KEY_C)
	for a in g._saved_keys:
		var ev := event_from_code(g, str(g._saved_keys[a]))
		if ev != null and InputMap.has_action(a):
			InputMap.action_erase_events(a)
			InputMap.action_add_event(a, ev)


static func event_code(g: GameState, ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return "k:%d" % (k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	if ev is InputEventMouseButton:
		return "m:%d" % (ev as InputEventMouseButton).button_index
	return ""


static func event_from_code(g: GameState, code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	if parts[0] == "k":
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1]) as Key
		return k
	if parts[0] == "m":
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1]) as MouseButton
		return m
	return null


## Shown on the rebind buttons, e.g. "W" or "Mouse 1 / C".
static func binding_text(g: GameState, action: String) -> String:
	var out: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
			var shown := code if g.display_headless() else DisplayServer.keyboard_get_keycode_from_physical(code)
			out.append(OS.get_keycode_string(shown))
		elif ev is InputEventMouseButton:
			var b := (ev as InputEventMouseButton).button_index
			out.append({MOUSE_BUTTON_LEFT: "Mouse L", MOUSE_BUTTON_RIGHT: "Mouse R", MOUSE_BUTTON_MIDDLE: "Mouse M"}.get(b, "Mouse %d" % b))
	return " / ".join(out) if not out.is_empty() else "—"


## One key or mouse button per action. If another rebindable action already uses it, that action
## gets this one's old binding (swap). Returns the swapped action's label, or "".
static func rebind(g: GameState, action: String, ev: InputEvent) -> String:
	var code := event_code(g, ev)
	if code == "" or not InputMap.has_action(action):
		return ""
	var old := InputMap.action_get_events(action)
	var swapped := ""
	for pair in g.REBIND_ACTIONS:
		var other: String = pair[0]
		if other == action:
			continue
		for oe in InputMap.action_get_events(other):
			if event_code(g, oe) == code:
				InputMap.action_erase_event(other, oe)
				if not old.is_empty():
					InputMap.action_add_event(other, old[0])
				g._saved_keys[other] = first_code(g, other)
				swapped = pair[1]
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event_from_code(g, code))
	g._saved_keys[action] = code
	g.save_settings()
	return swapped


static func first_code(g: GameState, action: String) -> String:
	var evs := InputMap.action_get_events(action)
	return event_code(g, evs[0]) if not evs.is_empty() else ""


static func reset_bindings(g: GameState) -> void:
	g._saved_keys.clear()
	for pair in g.REBIND_ACTIONS:
		InputMap.action_erase_events(pair[0])
	bind_inputs(g)
	g.save_settings()


static func key(g: GameState, action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if has_key(g, action, keycode):
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


static func mouse(g: GameState, action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if has_mouse(g, action, button):
		return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


static func has_key(g: GameState, action: String, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


static func has_mouse(g: GameState, action: String, button: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button:
			return true
	return false
