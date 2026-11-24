class_name KillcamVhs
extends RefCounted
## #317: the VHS fast-forward overlay of the final killcam, pulled out of `scripts/killcam.gd` (#258).
## Scanlines, a rolling tracking band, tape noise that flickers per frame and a camcorder OSD, all scaled
## by `amount` so the effect fades in instead of popping. Nothing but rectangles and two strings, so it
## costs nothing next to the replay itself. Static and stateless: `Killcam` decides how much tape there
## is (`_tape_amount`) and passes its own playback clock in.


## Paints the tape over `canvas`. `amount` is 0..1 (0 draws nothing), `real_t` the seconds spent in the
## replay (drives the noise and the OSD clock), `bar_h` the height of the bottom name bar.
static func paint(canvas: Control, amount: float, real_t: float, bar_h: float) -> void:
	if amount <= 0.001:
		return
	var w := canvas.size.x
	var h := canvas.size.y
	var y := 0.0
	while y < h:
		canvas.draw_rect(Rect2(0.0, y, w, 1.0), Color(0, 0, 0, 0.16 * amount))
		y += 3.0
	# The tracking band rolls up the frame: the artefact that says "tape" more than noise does.
	var band := fmod(real_t * 0.32, 1.35)
	var by := (band - 0.15) * h
	canvas.draw_rect(Rect2(0.0, by, w, 24.0), Color(1, 1, 1, 0.05 * amount))
	canvas.draw_rect(Rect2(0.0, by + 24.0, w, 2.0), Color(0, 0, 0, 0.3 * amount))
	# Tape noise: one-frame dashes, reseeded every frame so they crawl.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(real_t * 1000.0) + 7
	for i in 16:
		var nx := rng.randf() * w
		var ny := rng.randf() * h
		canvas.draw_rect(Rect2(nx, ny, rng.randf_range(8.0, 46.0), 1.0), Color(1, 1, 1, 0.16 * amount))
	# Camcorder OSD, bottom left above the name bar, like the tape is being fast-forwarded by hand.
	# ">>" and not a triangle: the fallback font has no play glyph (#258).
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(28.0, h - bar_h - 22.0), ">>  SP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.8 * amount))
	var tc := "%02d:%02d" % [int(real_t / 60.0), int(real_t) % 60]
	canvas.draw_string(font, Vector2(28.0, h - bar_h + 2.0), tc, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55 * amount))
