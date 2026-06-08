shader_type canvas_item;

// Keys out the near-white background of JPG sprite frames (which carry no alpha
// of their own). Any pixel whose DARKEST channel is brighter than `threshold`
// fades toward transparent; `softness` gives the cut a smooth anti-aliased
// edge. Tuned for pure-white backdrops — mid/light-gray detail (the barnacles)
// keeps a low enough min-channel to stay opaque.
uniform float threshold : hint_range(0.0, 1.0) = 0.90;
uniform float softness : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = min(c.r, min(c.g, c.b));
	float keep = 1.0 - smoothstep(threshold, threshold + softness, m);
	// COLOR enters as the node modulate — multiply through it so the hit-flash
	// tint (and any future modulate) still applies on top of the keyed texture.
	COLOR = vec4(c.rgb * COLOR.rgb, c.a * keep * COLOR.a);
}
