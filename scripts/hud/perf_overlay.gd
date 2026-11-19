class_name PerfOverlay
extends RefCounted
## Debug overlay text (Settings > HUD > Show FPS): fps, the frame the engine measured, the CPU time it
## took, physics time and the draw-call count. Frame ms well above cpu ms means the GPU is behind;
## frame ms and cpu ms together mean the CPU is. The HUD owns the label (bottom-right, so it never
## lands on the minimap) and asks for the text each frame.

var _gpu_measure := false


## The overlay's text for `vp` at the level in Game.perf_overlay (fps only, + frame time, or all).
func text(vp: Viewport, delta: float) -> String:
	var fps := Engine.get_frames_per_second()
	if Game.perf_overlay <= 1:
		return "%d fps" % fps
	var frame_ms := maxf(delta, 0.0001) * 1000.0
	if Game.perf_overlay == 2:
		return "%d fps   %.1f ms" % [fps, frame_ms]
	var cpu_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var gpu_ms := gpu_ms(vp)
	var bound := hint(frame_ms, cpu_ms, gpu_ms, DisplayServer.screen_get_refresh_rate(), Game.vsync)
	# Which renderer and GPU are actually running: two builds of the same code can differ here, and a
	# performance report has to name it. RenderingServer, not ProjectSettings: the project setting is
	# the build default and does not change when the game is started with --rendering-method.
	var method := RenderingServer.get_current_rendering_method()
	var adapter := RenderingServer.get_video_adapter_name()
	return "%d fps   %.1f ms   [%s]\ncpu %.1f ms   gpu %.1f ms   physics %.1f ms\ndraws %d   prims %dk\n%s · %s" % [
		fps, frame_ms, bound, cpu_ms, gpu_ms, phys_ms, draws, roundi(float(prims) / 1000.0), method, adapter
	]


## The GPU time of the last frame, measured by the engine (0 when the driver does not report it).
## Turns the measurement on the first time it is asked.
func gpu_ms(vp: Viewport) -> float:
	if vp == null:
		return 0.0
	var rid := vp.get_viewport_rid()
	if not _gpu_measure:
		RenderingServer.viewport_set_measure_render_time(rid, true)
		_gpu_measure = true
	return RenderingServer.viewport_get_measured_render_time_gpu(rid)


## Which side is actually behind. Frame time alone cannot answer it: with V-Sync on the frame time is
## the refresh interval most of the time, so calling that "[gpu]" blames the GPU for a vertical blank.
## Refresh rate is a parameter so the rule can be tested on a headless box, where it is 0.
static func hint(frame_ms: float, cpu_ms: float, gpu_ms: float, refresh_hz: float, vsync: bool) -> String:
	if vsync and refresh_hz > 1.0:
		var period := 1000.0 / refresh_hz
		if absf(frame_ms - period) <= period * 0.08:
			return "vsync"
	if gpu_ms > 0.0:
		return "gpu" if gpu_ms >= cpu_ms else "cpu"
	# No GPU timing available: a frame that costs much more than the CPU work has to be waiting on it.
	return "gpu" if frame_ms > cpu_ms * 1.35 else "cpu"
