shader_type canvas_item;

// Main color — default alien teal #2EC4A0
uniform vec4 water_color : source_color = vec4(0.18, 0.769, 0.627, 1.0);

// Ripple animation
uniform float ripple_speed : hint_range(0.0, 5.0) = 1.2;
uniform float ripple_scale : hint_range(0.1, 10.0) = 3.0;
uniform float ripple_strength : hint_range(0.0, 0.1) = 0.025;

// Glint/shimmer dots
uniform float glint_intensity : hint_range(0.0, 1.0) = 0.15;

// Overall transparency
uniform float alpha : hint_range(0.0, 1.0) = 0.38;

// Shoreline: 0.0 = full tile water, 1.0 = bottom-portion only with wavy edge
uniform float shoreline_blend : hint_range(0.0, 1.0) = 0.0;
// Y position (0=top, 1=bottom) where the shoreline edge sits
uniform float shoreline_position : hint_range(0.0, 1.0) = 0.5;
// How soft/wide the shoreline wave transition is
uniform float shoreline_softness : hint_range(0.0, 0.5) = 0.12;

void fragment() {
	vec2 uv = UV;
	float t = TIME * ripple_speed;

	// Four overlapping sine/cosine waves for organic ripple motion
	float wave1 = sin(uv.x * ripple_scale * 6.28318 + t) * ripple_strength;
	float wave2 = cos(uv.y * ripple_scale * 4.71239 + t * 0.73) * ripple_strength;
	float wave3 = sin((uv.x + uv.y) * ripple_scale * 3.14159 + t * 1.31) * ripple_strength * 0.5;
	float wave4 = cos((uv.x - uv.y) * ripple_scale * 2.0 + t * 0.91) * ripple_strength * 0.3;

	// Distorted UV for glint sampling
	vec2 distorted_uv = uv + vec2(wave1 + wave3, wave2 + wave4);

	// Ripple brightness: waves cause slight lightening/darkening of the water
	float ripple_bright = clamp(
		(wave1 + wave2 + wave3) / (ripple_strength * 2.5) * 0.5 + 0.5,
		0.0, 1.0
	);

	vec4 color = water_color;
	color.rgb = mix(color.rgb * 0.8, color.rgb * 1.2, ripple_bright);

	// Glint dots: two overlapping high-frequency patterns threshold into sparkles
	float glint1 = sin(distorted_uv.x * 47.0 + TIME * 3.1) * sin(distorted_uv.y * 43.0 + TIME * 2.7);
	float glint2 = sin(distorted_uv.x * 31.0 - TIME * 2.3) * cos(distorted_uv.y * 37.0 + TIME * 1.9);
	float glint = step(0.85, glint1) * 0.7 + step(0.88, glint2) * 0.3;
	glint *= glint_intensity;
	// Warm-tinted glint (slightly golden) to pop against the teal water
	color.rgb += vec3(glint * 1.2, glint * 1.0, glint * 0.7);

	color.a = alpha;

	// Shoreline: blend between full-tile water (0) and bottom-only water (1).
	// The edge is a smooth wavy line animated with the ripple waves.
	if (shoreline_blend > 0.001) {
		float shore_wave = sin(uv.x * ripple_scale * 5.0 + t * 1.8) * shoreline_softness * 0.5;
		float shore_mask = smoothstep(
			shoreline_position - shoreline_softness + shore_wave,
			shoreline_position + shoreline_softness * 0.5 + shore_wave,
			uv.y  // uv.y=0 is top of tile, 1 is bottom — water fades in downward
		);
		color.a *= mix(1.0, shore_mask, shoreline_blend);
	}

	COLOR = color;
}
