class_name GameSettings
extends RefCounted
## Settings file and display (#106): load/save user settings, window mode, resolution, vsync/fps,
## render scale, shadows. Static helpers on the Game autoload `g`; Game keeps the values and wrappers.


## Reads user://settings.cfg. Missing keys keep the defaults, so an older file (audio + mouse
## only) still loads. Applies audio and, unless this process is headless, the video settings.
static func load_settings(g: GameState) -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		g.master_vol = clampf(float(cfg.get_value("audio", "master", 1.0)), 0.0, 1.0)
		g.sfx_vol = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
		g.enemies_vol = clampf(float(cfg.get_value("audio", "enemies", g.ENEMIES_VOL_DEFAULT)), 0.0, g.ENEMIES_VOL_MAX)
		g.mouse_sens = clampf(float(cfg.get_value("input", "mouse_sens", 1.0)), g.MOUSE_SENS_MIN, g.MOUSE_SENS_MAX)
		g.ads_sens = clampf(float(cfg.get_value("input", "ads_sens", 0.45)), g.ADS_SENS_MIN, g.ADS_SENS_MAX)
		g.invert_y = bool(cfg.get_value("input", "invert_y", false))
		var m := StringName(str(cfg.get_value("match", "map", String(Maps.DEFAULT))))
		g.last_map = m if Maps.has(m) else Maps.DEFAULT
		g.last_mode = clampi(int(cfg.get_value("match", "mode", g.MODE_TDM)), g.MODE_TDM, g.MODE_LAST)
		g.last_kills = clampi(int(cfg.get_value("match", "kills", g.default_kills_for(g.last_mode))), g.KILLS_MIN, g.KILLS_MAX)
		g.last_time_min = clampi(int(cfg.get_value("match", "time_min", 10)), g.TIME_MIN_MINUTES, g.TIME_MAX_MINUTES)
		g.last_bots = clampi(int(cfg.get_value("match", "bots", g.BOT_COUNT_DEFAULT)), 0, g.BOT_COUNT_MAX)
		g.last_bot_difficulty = clampi(int(cfg.get_value("match", "bot_difficulty", g.BOT_MEDIUM)), g.BOT_EASY, g.BOT_HARD)
		g.bot_difficulty = g.last_bot_difficulty
		g.kill_limit = g.last_kills
		g.round_time = float(g.last_time_min * 60)
		g.bot_count = g.last_bots
		g.profile_name = g.clean_name(str(cfg.get_value("profile", "name", g.profile_name)))
		g.recent_servers = PackedStringArray()
		for e in cfg.get_value("net", "recent", PackedStringArray()):
			if str(e).strip_edges() != "" and g.recent_servers.size() < g.RECENT_SERVERS_MAX:
				g.recent_servers.append(str(e).strip_edges())
		g.last_server = str(cfg.get_value("net", "last", "")).strip_edges()
		if cfg.has_section_key("net", "favorites"):
			g.favorite_servers = PackedStringArray()
			for e in cfg.get_value("net", "favorites", PackedStringArray()):
				if str(e).strip_edges() != "":
					g.favorite_servers.append(str(e).strip_edges())
		g.player_name = g.profile_name
		g.window_mode = clampi(int(cfg.get_value("video", "window_mode", g.WINDOW_WINDOWED)), g.WINDOW_WINDOWED, g.WINDOW_FULLSCREEN)
		var w := int(cfg.get_value("video", "width", g.window_size.x))
		var h := int(cfg.get_value("video", "height", g.window_size.y))
		if w < 640 or h < 480:
			w = 1600
			h = 900
		g.window_size = Vector2i(w, h)
		g.vsync = bool(cfg.get_value("video", "vsync", true))
		g.max_fps = snap_fps(g, int(cfg.get_value("video", "max_fps", 0)))
		g.fov = clampf(roundf(float(cfg.get_value("video", "fov", 90.0))), g.FOV_MIN, g.FOV_MAX)
		g.render_scale = snap_scale(g, float(cfg.get_value("video", "render_scale", 1.0)))
		g.msaa = clampi(int(cfg.get_value("video", "msaa", 2)), 0, 3)
		g.show_fps = bool(cfg.get_value("hud", "show_fps", true))
		g.gfx_quality = clampi(int(cfg.get_value("video", "quality", 2)), 0, 2)
		g.view_sway = clampi(int(cfg.get_value("video", "view_sway", 2)), 0, 2)
		g.music_vol = clampf(float(cfg.get_value("audio", "music", 1.0)), 0.0, 1.0)
		g.ui_vol = clampf(float(cfg.get_value("audio", "ui", 1.0)), 0.0, 1.0)
		g.shadow_quality = clampi(int(cfg.get_value("video", "shadows", 0)), 0, g.SHADOW_NAMES.size() - 1)
		g.crosshair_color = clampi(int(cfg.get_value("hud", "crosshair_color", 0)), 0, g.CROSSHAIR_COLORS.size() - 1)
		g.crosshair_style = clampi(int(cfg.get_value("hud", "crosshair_style", 0)), 0, g.CROSSHAIR_STYLES.size() - 1)
		g.crosshair_size = clampf(float(cfg.get_value("hud", "crosshair_size", 1.0)), 0.5, 2.0)
		g.show_minimap = bool(cfg.get_value("hud", "minimap", true))
		g.show_killfeed = bool(cfg.get_value("hud", "killfeed", true))
		g.colorblind = clampi(int(cfg.get_value("access", "colorblind", 0)), 0, g.COLORBLIND_NAMES.size() - 1)
		g.reduce_shake = bool(cfg.get_value("access", "reduce_shake", false))
		g._saved_keys = {}
		if cfg.has_section("keys"):
			for a in cfg.get_section_keys("keys"):
				g._saved_keys[a] = str(cfg.get_value("keys", a, ""))
	g.apply_audio()
	var size_before := g.window_size
	apply_display(g)
	# A size that does not fit this monitor is replaced; remember the one we actually used.
	if g.window_size != size_before:
		save_settings(g)


## Rewrites the whole file from memory. Every key load_settings reads has to be written here.
static func save_settings(g: GameState) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", g.master_vol)
	cfg.set_value("audio", "sfx", g.sfx_vol)
	cfg.set_value("audio", "enemies", g.enemies_vol)
	cfg.set_value("input", "mouse_sens", g.mouse_sens)
	cfg.set_value("input", "ads_sens", g.ads_sens)
	cfg.set_value("input", "invert_y", g.invert_y)
	cfg.set_value("match", "map", String(g.last_map))
	cfg.set_value("match", "mode", g.last_mode)
	cfg.set_value("match", "kills", g.last_kills)
	cfg.set_value("match", "time_min", g.last_time_min)
	cfg.set_value("match", "bots", g.last_bots)
	cfg.set_value("match", "bot_difficulty", g.last_bot_difficulty)
	cfg.set_value("profile", "name", g.profile_name)
	cfg.set_value("net", "recent", g.recent_servers)
	cfg.set_value("net", "last", g.last_server)
	cfg.set_value("net", "favorites", g.favorite_servers)
	cfg.set_value("video", "window_mode", g.window_mode)
	cfg.set_value("video", "width", g.window_size.x)
	cfg.set_value("video", "height", g.window_size.y)
	cfg.set_value("video", "vsync", g.vsync)
	cfg.set_value("video", "max_fps", g.max_fps)
	cfg.set_value("video", "fov", g.fov)
	cfg.set_value("video", "render_scale", g.render_scale)
	cfg.set_value("video", "msaa", g.msaa)
	cfg.set_value("hud", "show_fps", g.show_fps)
	cfg.set_value("video", "quality", g.gfx_quality)
	cfg.set_value("video", "view_sway", g.view_sway)
	cfg.set_value("audio", "music", g.music_vol)
	cfg.set_value("audio", "ui", g.ui_vol)
	cfg.set_value("video", "shadows", g.shadow_quality)
	cfg.set_value("hud", "crosshair_color", g.crosshair_color)
	cfg.set_value("hud", "crosshair_style", g.crosshair_style)
	cfg.set_value("hud", "crosshair_size", g.crosshair_size)
	cfg.set_value("hud", "minimap", g.show_minimap)
	cfg.set_value("hud", "killfeed", g.show_killfeed)
	cfg.set_value("access", "colorblind", g.colorblind)
	cfg.set_value("access", "reduce_shake", g.reduce_shake)
	for a in g._saved_keys:
		cfg.set_value("keys", a, g._saved_keys[a])
	cfg.save("user://settings.cfg")


## Shadow override on top of Gfx. Auto leaves Gfx's choice alone.
static func apply_shadows(g: GameState, map: Node) -> void:
	if g.shadow_quality == 0:
		if map:
			for sun in map.find_children("*", "DirectionalLight3D", true, false):
				var l := sun as DirectionalLight3D
				if l.has_meta(&"shadow_base"):
					l.shadow_enabled = bool(l.get_meta(&"shadow_base"))
		return
	match g.shadow_quality:
		2:
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		3:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		4:
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	if map == null:
		return
	for sun in map.find_children("*", "DirectionalLight3D", true, false):
		var l := sun as DirectionalLight3D
		if not l.has_meta(&"shadow_base"):
			l.set_meta(&"shadow_base", l.shadow_enabled)
		l.shadow_enabled = g.shadow_quality != 1 and bool(l.get_meta(&"shadow_base"))


## Presets that fit the current monitor, plus that monitor's own size when it is not already listed.
static func resolution_choices(g: GameState) -> Array:
	var screen := Vector2i(1920, 1080)
	if not g.display_headless():
		screen = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return resolutions_fitting(g, screen)


static func resolutions_fitting(g: GameState, screen: Vector2i) -> Array:
	var out: Array[Vector2i] = []
	for r in g.RESOLUTIONS:
		var size := r as Vector2i
		if size.x <= screen.x and size.y <= screen.y:
			out.append(size)
	var listed := false
	for size in out:
		if size == screen:
			listed = true
			break
	if not listed and screen.x >= 640 and screen.y >= 480:
		out.append(screen)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	if out.is_empty():
		out.append(Vector2i(mini(maxi(screen.x, 640), 1280), mini(maxi(screen.y, 480), 720)))
	return out


## Window, VSync, the FPS cap, 3D scale and MSAA. Headless returns immediately; main.gd then
## pins a dedicated server to 60 fps. A saved size bigger than this monitor is replaced with
## the largest preset that fits, and load_settings writes that back.
static func apply_display(g: GameState) -> void:
	if g.display_headless():
		return
	apply_vsync_and_fps(g)
	apply_window(g)
	apply_render(g)


static func apply_vsync_and_fps(g: GameState) -> void:
	if g.display_headless():
		return
	var want_vsync := DisplayServer.VSYNC_ENABLED if g.vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != want_vsync:
		DisplayServer.window_set_vsync_mode(want_vsync)
	if Engine.max_fps != g.max_fps:
		Engine.max_fps = g.max_fps


static func apply_window(g: GameState) -> void:
	var screen_id := DisplayServer.window_get_current_screen()
	var screen := DisplayServer.screen_get_size(screen_id)
	var fit := clamp_window_size(g, g.window_size, screen)
	if fit != g.window_size:
		g.window_size = fit
	var mode_now := DisplayServer.window_get_mode()
	if g.window_mode == g.WINDOW_BORDERLESS:
		# Borderless follows the monitor. The stored size is for windowed / exclusive only.
		if mode_now != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if g.window_mode == g.WINDOW_FULLSCREEN:
		if mode_now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN and DisplayServer.window_get_size() == g.window_size:
			return
		# Leave exclusive before changing size, or the mode switch keeps the old resolution.
		if mode_now != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(g.window_size)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		return
	var size_now := DisplayServer.window_get_size()
	if mode_now != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	if size_now != g.window_size:
		DisplayServer.window_set_size(g.window_size)
		var origin := DisplayServer.screen_get_position(screen_id)
		DisplayServer.window_set_position(origin + (screen - g.window_size) / 2)


static func clamp_window_size(g: GameState, size: Vector2i, screen: Vector2i) -> Vector2i:
	if size.x >= 640 and size.y >= 480 and size.x <= screen.x and size.y <= screen.y:
		return size
	var choices := resolutions_fitting(g, screen)
	var best: Vector2i = choices[0]
	var best_area := -1
	for choice in choices:
		var area: int = int(choice.x) * int(choice.y)
		if area > best_area:
			best = choice
			best_area = area
	return best


## 3D render scale and MSAA on the root viewport. 2D (HUD, menus) stays at the window resolution.
## Skip writes that already match: assigning msaa_3d on a live Vulkan viewport can SIGSEGV.
static func apply_render(g: GameState) -> void:
	if not g.is_inside_tree() or g.display_headless():
		return
	var root := g.get_tree().root
	if root.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if not is_equal_approx(root.scaling_3d_scale, g.render_scale):
		root.scaling_3d_scale = g.render_scale
	var want_msaa := g.msaa as Viewport.MSAA
	if root.msaa_3d != want_msaa:
		root.msaa_3d = want_msaa
	Gfx.apply_global(g.gfx_quality)
	var main := root.get_node_or_null(^"Main")
	var map_node: Node = null
	if main and "map_node" in main:
		map_node = main.map_node
		Gfx.apply_map(map_node, g.gfx_quality)
	apply_shadows(g, map_node)


static func snap_fps(g: GameState, v: int) -> int:
	v = clampi(v, 0, g.FPS_CAP_MAX)
	return int(round(float(v) / 10.0)) * 10


static func snap_scale(g: GameState, v: float) -> float:
	return clampf(round(clampf(v, 0.5, 1.0) * 20.0) / 20.0, 0.5, 1.0)
