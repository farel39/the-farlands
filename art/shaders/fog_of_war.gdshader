shader_type canvas_item;

uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.03, 1.0);

uniform vec2 itf_origin = vec2(0.0);
uniform vec2 itf_x = vec2(1.0, 0.0);
uniform vec2 itf_y = vec2(0.0, 1.0);
uniform vec2 world_size = vec2(12800.0, 12800.0);

uniform sampler2D explored_tex : filter_nearest;

void fragment() {
	vec2 frag_px = UV * viewport_size;
	vec2 world_pos = itf_origin + itf_x * frag_px.x + itf_y * frag_px.y;
	vec2 grid_uv = clamp(world_pos / world_size, vec2(0.0), vec2(1.0));
	float explored = texture(explored_tex, grid_uv).r;

	// Explored: slight dark veil so memory areas feel darker than currently lit.
	// Unexplored: full fog.
	float fog_alpha = explored > 0.5 ? fog_color.a * 0.78 : fog_color.a;
	COLOR = vec4(fog_color.rgb, fog_alpha);
}
