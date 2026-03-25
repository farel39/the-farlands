shader_type canvas_item;

// Cardinal neighbour mask: bit0=N, bit1=E, bit2=S, bit3=W.
uniform int cardinal_mask : hint_range(0, 15) = 15;
// Diagonal neighbour mask: bit0=NE, bit1=SE, bit2=SW, bit3=NW.
uniform int diag_mask : hint_range(0, 15) = 15;
// How wide the fade zone is as a fraction of tile size.
uniform float fade_width : hint_range(0.0, 0.7) = 0.55;

void fragment() {
	vec2 uv = UV;

	// Cardinal edge fades
	float fade_n = ((cardinal_mask & 1) == 0) ? smoothstep(0.0, fade_width, uv.y)       : 1.0;
	float fade_e = ((cardinal_mask & 2) == 0) ? smoothstep(0.0, fade_width, 1.0 - uv.x) : 1.0;
	float fade_s = ((cardinal_mask & 4) == 0) ? smoothstep(0.0, fade_width, 1.0 - uv.y) : 1.0;
	float fade_w = ((cardinal_mask & 8) == 0) ? smoothstep(0.0, fade_width, uv.x)       : 1.0;

	float fade_ne = ((diag_mask & 1) == 0 && (cardinal_mask & 1) != 0 && (cardinal_mask & 2) != 0)
		? smoothstep(0.0, fade_width, length(vec2(1.0 - uv.x, uv.y))) : 1.0;
	float fade_se = ((diag_mask & 2) == 0 && (cardinal_mask & 4) != 0 && (cardinal_mask & 2) != 0)
		? smoothstep(0.0, fade_width, length(vec2(1.0 - uv.x, 1.0 - uv.y))) : 1.0;
	float fade_sw = ((diag_mask & 4) == 0 && (cardinal_mask & 4) != 0 && (cardinal_mask & 8) != 0)
		? smoothstep(0.0, fade_width, length(vec2(uv.x, 1.0 - uv.y))) : 1.0;
	float fade_nw = ((diag_mask & 8) == 0 && (cardinal_mask & 1) != 0 && (cardinal_mask & 8) != 0)
		? smoothstep(0.0, fade_width, length(vec2(uv.x, uv.y))) : 1.0;

	COLOR = texture(TEXTURE, uv);
	COLOR.a *= fade_n * fade_e * fade_s * fade_w * fade_ne * fade_se * fade_sw * fade_nw;
}
