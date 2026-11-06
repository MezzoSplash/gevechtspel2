shader_type canvas_item;
// Speed lines: procedural radial streaks while the local player moves fast (Game.speed_fx).
// Nothing is sampled (no hint_screen_texture), so this is cheap and headless-friendly: the
// intensity comes from Player.speed_lines_intensity on the pawn, not from what is on screen.
// max_alpha stays low on purpose, so even a full-intensity pass is see-through and the HUD and
// the crosshair keep reading.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float streaks = 44.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	// Work in pixels, so the ring is round on any window shape instead of elliptical.
	p.x *= SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
	float r = length(p) * 2.0;
	// One thin spoke per angular slice.
	float ang = atan(p.y, p.x) / TAU + 0.5;
	float spoke = abs(fract(ang * streaks) - 0.5) * 2.0;
	float line = smoothstep(0.90, 1.0, spoke);
	// Nothing near the centre (that is where you aim) and nothing way out in the corners.
	float ring = smoothstep(0.30, 0.95, r) * (1.0 - smoothstep(0.80, 1.30, r));
	// intensity 0 lands on alpha 0, so there is no early out: a Godot fragment() takes no `return`.
	COLOR = vec4(1.0, 1.0, 1.0, line * ring * intensity * max_alpha);
}
