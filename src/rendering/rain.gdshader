// Rain overlay shader — ADR-0001 CanvasLayer 20
// Subtle animated rain streaks over the ink wash scene.
shader_type canvas_item;

uniform float rain_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float time_value : hint_range(0.0, 300.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 screen = texture(SCREEN_TEXTURE, uv);

	// Rain streaks — vertical lines with slight wave
	float rain_speed = time_value * 2.5;
	float streak_scale = 40.0;

	// Two layers of rain at different scales for depth
	float rain_layer1 = 0.0;
	float rain_layer2 = 0.0;

	// Layer 1 — heavy rain, close
	vec2 p1 = vec2(uv.x * streak_scale, uv.y * streak_scale * 0.5 - rain_speed);
	float cell_x1 = floor(p1.x);
	float offset1 = hash21(vec2(cell_x1, 0.0));
	float drop1 = smoothstep(0.02, 0.0, abs(p1.x - cell_x1 - 0.5 - (offset1 - 0.5) * 0.6));
	float brightness1 = hash21(vec2(cell_x1, floor(p1.y)));
	drop1 *= step(0.3, brightness1);
	rain_layer1 = drop1;

	// Layer 2 — lighter rain, further
	vec2 p2 = vec2(uv.x * streak_scale * 1.8 + 10.0, uv.y * streak_scale * 0.8 - rain_speed * 0.7);
	float cell_x2 = floor(p2.x);
	float offset2 = hash21(vec2(cell_x2, 1.0));
	float drop2 = smoothstep(0.03, 0.0, abs(p2.x - cell_x2 - 0.5 - (offset2 - 0.5) * 0.5));
	float brightness2 = hash21(vec2(cell_x2, floor(p2.y)));
	drop2 *= step(0.4, brightness2);
	rain_layer2 = drop2 * 0.5;

	float rain_total = (rain_layer1 + rain_layer2) * rain_intensity;

	// Slight darkening from rain atmosphere
	vec3 rain_color = screen.rgb * (1.0 - rain_total * 0.15);
	// Add bright streak highlights
	rain_color += vec3(0.1, 0.1, 0.12) * rain_total;

	// Blend rain with original
	vec3 final_color = mix(screen.rgb, rain_color, rain_intensity * 0.8);

	COLOR = vec4(final_color, 1.0);
}
