shader_type canvas_item;
// Round-start freeze: the world in greyscale, back to colour when the round goes live (#63).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 grey = vec3(g) * 0.92 + 0.02; // a touch flatter, so it reads as "not yet"
	COLOR = vec4(mix(c, grey, amount), 1.0);
}
