shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.8, 0.5);
uniform vec4 haze_color : source_color = vec4(1.0, 0.9, 0.65, 0.18);
uniform sampler2D noise_tex : hint_default_white, filter_linear, repeat_enable;
uniform float haze_amount : hint_range(0.0, 1.0) = 0.5;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.35;
uniform float edge_soft : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	float along = UV.x;
	float across = abs(UV.y - 0.5) * 2.0;
	float half_w = max(along, 0.025);
	float edge = 1.0 - smoothstep(half_w * (1.0 - edge_soft), half_w, across);
	// GLES3 rejects early exits from fragment(); outside the cone, edge is 0 so alpha is 0.
	float len_fade = 1.0 - smoothstep(0.22, 1.0, along);
	float core = exp(-across * 4.8 / max(along, 0.05)) * (1.0 - smoothstep(0.0, 0.48, along));
	vec2 n_uv = UV * vec2(1.7, 3.1) + vec2(TIME * 0.035, TIME * 0.012);
	float n = texture(noise_tex, n_uv).r;
	float vol = smoothstep(0.22, 0.88, n) * edge * len_fade * haze_amount;
	vec2 d_uv = UV * vec2(7.0, 11.0) + vec2(-TIME * 0.11, TIME * 0.045);
	float mote = smoothstep(0.86, 0.97, texture(noise_tex, d_uv).r) * edge * dust_amount;
	vec3 col = mix(haze_color.rgb, core_color.rgb, clamp(core, 0.0, 1.0));
	float a = clamp(haze_color.a * vol + core_color.a * core * edge + mote * 0.75, 0.0, 1.0);
	COLOR = vec4(col, a);
}
