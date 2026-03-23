shader_type canvas_item;

// Cardinal neighbour mask: bit0=N, bit1=E, bit2=S, bit3=W.
// Bit=1 → that side touches another rock/pool (no fade).
// Bit=0 → that side faces open sand (apply smoothstep fade).
uniform int cardinal_mask : hint_range(0, 15) = 0;

// How wide the fade zone is as a fraction of tile size.
uniform float fade_width : hint_range(0.0, 0.5) = 0.3;

void fragment() {
	vec2 uv = UV;

	float fade_n = ((cardinal_mask & 1) == 0) ? smoothstep(0.0, fade_width, uv.y)       : 1.0;
	float fade_e = ((cardinal_mask & 2) == 0) ? smoothstep(0.0, fade_width, 1.0 - uv.x) : 1.0;
	float fade_s = ((cardinal_mask & 4) == 0) ? smoothstep(0.0, fade_width, 1.0 - uv.y) : 1.0;
	float fade_w = ((cardinal_mask & 8) == 0) ? smoothstep(0.0, fade_width, uv.x)       : 1.0;

	COLOR = texture(TEXTURE, uv);
	COLOR.a *= fade_n * fade_e * fade_s * fade_w;
}
