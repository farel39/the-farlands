shader_type canvas_item;

// Cardinal neighbor bitmask: bit 0=N, bit 1=E, bit 2=S, bit 3=W
// A bit is 1 when that neighbour is also dirt (no rounding on that edge).
// A bit is 0 when that neighbour is sand (round the corners touching that edge).
uniform int cardinal_mask : hint_range(0, 15) = 15;

// How large the rounded corner arc is, as a fraction of tile size (0–0.5).
uniform float radius : hint_range(0.05, 0.49) = 0.32;

void fragment() {
	vec2 uv = UV;

	bool sand_n = (cardinal_mask & 1) == 0;
	bool sand_e = (cardinal_mask & 2) == 0;
	bool sand_s = (cardinal_mask & 4) == 0;
	bool sand_w = (cardinal_mask & 8) == 0;

	// Top-left corner: round only when BOTH north AND west are sand.
	if ((sand_n && sand_w) && uv.x < radius && uv.y < radius) {
		if (length(uv - vec2(radius, radius)) > radius) discard;
	}
	// Top-right corner: round only when BOTH north AND east are sand.
	if ((sand_n && sand_e) && uv.x > 1.0 - radius && uv.y < radius) {
		if (length(uv - vec2(1.0 - radius, radius)) > radius) discard;
	}
	// Bottom-left corner: round only when BOTH south AND west are sand.
	if ((sand_s && sand_w) && uv.x < radius && uv.y > 1.0 - radius) {
		if (length(uv - vec2(radius, 1.0 - radius)) > radius) discard;
	}
	// Bottom-right corner: round only when BOTH south AND east are sand.
	if ((sand_s && sand_e) && uv.x > 1.0 - radius && uv.y > 1.0 - radius) {
		if (length(uv - vec2(1.0 - radius, 1.0 - radius)) > radius) discard;
	}

	COLOR = COLOR;
}
