extends Node
## The [cpu]/[gpu] hint in the perf overlay. Frame time alone cannot answer "which side is behind":
## with V-Sync on the frame time is the refresh interval, and calling that a GPU bottleneck is wrong.
##   godot --headless res://tools/check_perf_hint.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _hint(frame_ms: float, cpu_ms: float, gpu_ms: float, hz: float, vsync: bool) -> String:
	return Hud.perf_hint(frame_ms, cpu_ms, gpu_ms, hz, vsync)


func _ready() -> void:
	# vsync on, hitting the refresh interval: that is waiting on the screen, not on the GPU.
	_ok(_hint(16.7, 5.0, 9.0, 60.0, true) == "vsync", "vsync on and on the refresh interval reads [vsync]")
	_ok(_hint(16.9, 5.0, 0.0, 60.0, true) == "vsync", "0.2 ms off the interval still reads [vsync]")
	# vsync on but nowhere near the interval (dropped frames): the hint has to answer normally.
	_ok(_hint(31.0, 5.0, 20.0, 60.0, true) == "gpu", "vsync on and missing frames reads [gpu] when the GPU time is high")
	_ok(_hint(31.0, 28.0, 3.0, 60.0, true) == "cpu", "vsync on and missing frames reads [cpu] when the CPU time is high")
	# vsync off: measured GPU time wins over frame time.
	_ok(_hint(20.0, 5.0, 18.0, 60.0, false) == "gpu", "measured GPU time above CPU time reads [gpu]")
	_ok(_hint(20.0, 18.0, 6.0, 60.0, false) == "cpu", "measured GPU time below CPU time reads [cpu]")
	# No GPU timing: fall back to the frame-time rule.
	_ok(_hint(20.0, 5.0, 0.0, 60.0, false) == "gpu", "no GPU timing, frame far above CPU reads [gpu]")
	_ok(_hint(6.0, 5.0, 0.0, 60.0, false) == "cpu", "no GPU timing, frame near CPU reads [cpu]")
	# An unknown refresh rate must not turn everything into [vsync].
	_ok(_hint(16.7, 5.0, 0.0, 0.0, true) == "gpu", "unknown refresh rate falls through to the normal rule")

	print("PERF HINT CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
