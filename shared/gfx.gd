class_name Gfx
## Graphics quality. The map scene carries the full look (sky, AgX, SSAO, glow, depth fog,
## world paint); this switches the heavy parts per level. Low is close to the old flat look.
## Nothing here changes collision or anything the server simulates.

enum { LOW, MEDIUM, HIGH }
const NAMES := ["Low", "Medium", "High"]


## Global shader detail, shadow filter/size. Call once per level change (any viewport).
static func apply_global(level: int) -> void:
	RenderingServer.global_shader_parameter_set(&"world_detail", 0.0 if level == LOW else 1.0)
	match level:
		LOW:
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		MEDIUM:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		_:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)


## Per map: the scene's own wishes are remembered once, then capped by the level.
static func apply_map(map: Node, level: int) -> void:
	if map == null:
		return
	for we in map.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env == null:
			continue
		if not env.has_meta(&"gfx_base"):
			env.set_meta(&"gfx_base", {"ssao": env.ssao_enabled, "glow": env.glow_enabled, "fog": env.fog_enabled})
		var base: Dictionary = env.get_meta(&"gfx_base")
		env.ssao_enabled = bool(base.ssao) and level >= HIGH
		env.glow_enabled = bool(base.glow) and level >= MEDIUM
		env.fog_enabled = bool(base.fog) and level >= MEDIUM
	for sun in map.find_children("*", "DirectionalLight3D", true, false):
		var l := sun as DirectionalLight3D
		if not l.has_meta(&"gfx_dist"):
			l.set_meta(&"gfx_dist", l.directional_shadow_max_distance)
		l.directional_shadow_max_distance = minf(float(l.get_meta(&"gfx_dist")), 60.0 if level == LOW else 1000.0)
		l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if level == LOW else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
