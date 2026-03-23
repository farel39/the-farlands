shader_type canvas_item;

// Cardinal neighbour mask: bit0=N, bit1=E, bit2=S, bit3=W.
// Bit=1 → that side touches another dirt tile (no fade).
// Bit=0 → that side faces sand (apply smoothstep fade).
uniform int cardinal_mask : hint_range(0, 15) = 15;

// Diagonal neighbour mask: bit0=NE, bit1=SE, bit2=SW, bit3=NW.
// Bit=1 → that corner touches another dirt tile (no corner fade).
// Bit=0 → that corner faces sand (apply radial corner fade when both adjacent cardinals are dirt).
uniform int diag_mask : hint_range(0, 15) = 15;

// How wide the fade zone is as a fraction of tile size.
uniform float fade_width : hint_range(0.0, 0.5) = 0.4;

void fragment() {
	vec2 uv = UV;

	// Cardinal edge fades
	float fade_n = ((cardinal_mask & 1) == 0) ? smoothstep(0.0, fade_width, uv.y)       : 1.0;
	float fade_e = ((cardinal_mask & 2) == 0) ? smoothstep(0.0, fade_width, 1.0 - uv.x) : 1.0;
	float fade_s = ((cardinal_mask & 4) == 0) ? smoothstep(0.0, fade_width, 1.0 - uv.y) : 1.0;
	float fade_w = ((cardinal_mask & 8) == 0) ? smoothstep(0.0, fade_width, uv.x)       : 1.0;

	// Diagonal corner fades — only when the diagonal is sand AND both adjacent cardinals are dirt.
	// This prevents hard rectangular corners at concave patch boundaries.
	// NE corner (uv → 1,0): diag bit0, cardinals N(bit0) and E(bit1) must both be dirt.
	float fade_ne = ((diag_mask & 1) == 0 && (cardinal_mask & 1) != 0 && (cardinal_mask & 2) != 0)
		? smoothstep(0.0, fade_width, length(vec2(1.0 - uv.x, uv.y)))
		: 1.0;
	// SE corner (uv → 1,1): diag bit1, cardinals S(bit2) and E(bit1) must both be dirt.
	float fade_se = ((diag_mask & 2) == 0 && (cardinal_mask & 4) != 0 && (cardinal_mask & 2) != 0)
		? smoothstep(0.0, fade_width, length(vec2(1.0 - uv.x, 1.0 - uv.y)))
		: 1.0;
	// SW corner (uv → 0,1): diag bit2, cardinals S(bit2) and W(bit3) must both be dirt.
	float fade_sw = ((diag_mask & 4) == 0 && (cardinal_mask & 4) != 0 && (cardinal_mask & 8) != 0)
		? smoothstep(0.0, fade_width, length(vec2(uv.x, 1.0 - uv.y)))
		: 1.0;
	// NW corner (uv → 0,0): diag bit3, cardinals N(bit0) and W(bit3) must both be dirt.
	float fade_nw = ((diag_mask & 8) == 0 && (cardinal_mask & 1) != 0 && (cardinal_mask & 8) != 0)
		? smoothstep(0.0, fade_width, length(vec2(uv.x, uv.y)))
		: 1.0;

	COLOR = texture(TEXTURE, uv);
	COLOR.a *= fade_n * fade_e * fade_s * fade_w * fade_ne * fade_se * fade_sw * fade_nw;
}
