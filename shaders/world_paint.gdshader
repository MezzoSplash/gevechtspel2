// World paint: flat swatch colour plus large painted wear and simple cartoon patterns
// (brick courses, concrete slabs, corrugated ribs), all procedural in world space.
// No texture files. The albedo stays around the swatch (art guide: "slijtage in grote vlakken").
// global `world_detail` (0..1) comes from the graphics quality setting; 0 gives the flat swatch.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float world_detail;

uniform vec4 albedo : source_color = vec4(0.4, 0.4, 0.38, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.88;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// 0 plain, 1 brick, 2 concrete slabs, 3 corrugated ribs, 4 roof sheets, 5 asphalt grain
uniform int pattern = 0;
uniform float wear = 0.10;        // +- tone of the large blotches
uniform float line_dark = 0.30;   // how dark mortar / seams get
uniform float grain = 0.04;       // fine grain amplitude

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// 1 on a groove of half-width w around integer lines of t, anti-aliased with fwidth.
float groove(float t, float w) {
	float d = abs(fract(t + 0.5) - 0.5);
	float aa = fwidth(t) * 1.2;
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

// Pattern on one plane: uv.y is "up" for walls. Returns (line mask, per-cell tone).
vec2 plane_pattern(vec2 uv, bool wall) {
	if (pattern == 1) { // brick: 0.50 x 0.20 m, running bond (on floors: plain)
		if (!wall) return vec2(0.0, 0.0);
		float row = floor(uv.y / 0.20);
		float u = uv.x / 0.50 + 0.5 * mod(row, 2.0);
		float m = max(groove(uv.y / 0.20, 0.07), groove(u, 0.028));
		return vec2(m, hash2(vec2(floor(u), row)) - 0.5);
	} else if (pattern == 2) { // concrete slabs: 3.0 x 1.5 m on walls, 3 x 3 m on floors
		vec2 cell = wall ? vec2(3.0, 1.5) : vec2(3.0, 3.0);
		vec2 c = uv / cell;
		float m = max(groove(c.x, 0.004), groove(c.y, 0.007));
		return vec2(m, hash2(floor(c)) - 0.5);
	} else if (pattern == 3) { // corrugated: vertical ribs every 0.30 m
		if (!wall) return vec2(0.0, 0.0);
		float s = sin(uv.x / 0.30 * 6.2831853);
		float aa = clamp(fwidth(uv.x) / 0.30 * 3.0, 0.0, 1.0);
		return vec2(mix(smoothstep(0.2, 1.0, s) * 0.6, 0.15, aa), 0.0);
	} else if (pattern == 4) { // roof sheets 1.2 m wide with a seam
		float m = groove(uv.x / 1.2, 0.02);
		return vec2(m, hash2(vec2(floor(uv.x / 1.2), 7.0)) - 0.5);
	}
	return vec2(0.0, 0.0);
}

void fragment() {
	vec3 col = albedo.rgb;
	float rough = roughness;
	float k = clamp(world_detail, 0.0, 1.0);
	if (k > 0.001) {
		vec3 n = normalize(wnrm);
		vec3 w = pow(abs(n), vec3(6.0));
		w /= (w.x + w.y + w.z);
		vec2 px = plane_pattern(wpos.zy, true);
		vec2 py = plane_pattern(wpos.xz, false) * vec2(0.6, 1.0); // floor seams lighter
		vec2 pz = plane_pattern(wpos.xy, true);
		vec2 p = px * w.x + py * w.y + pz * w.z;
		// Large painted wear: two octaves, metres across.
		float big = vnoise3(wpos * 0.11) * 0.65 + vnoise3(wpos * 0.37 + 11.0) * 0.35;
		float tone = (big - 0.5) * 2.0 * wear + p.y * 0.07;
		float g = (hash3(floor(wpos * 40.0)) - 0.5) * grain;
		if (pattern == 5) g *= 2.5;
		float lum = 1.0 + (tone + g) * k;
		lum *= 1.0 - p.x * line_dark * k;
		col *= lum;
		rough = clamp(rough + p.x * 0.06 * k - (big - 0.5) * 0.06 * k, 0.0, 1.0);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic;
}
