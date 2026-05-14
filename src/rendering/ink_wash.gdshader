// Production ink wash shader — ADR-0001
// Post-processing effect for sumi-e visual identity.
// Knowledge accumulation: 0.0 = pure monochrome, 1.0 = full color.
shader_type canvas_item;

// How much color the player has recovered (0 = monochrome, 1 = full color)
uniform float knowledge_level : hint_range(0.0, 1.0) = 0.0;
// Time pressure intensity — darkens ink and increases bleeding
uniform float pressure_level : hint_range(0.0, 1.0) = 0.0;
// Elapsed time for animated effects
uniform float time_value : hint_range(0.0, 300.0) = 0.0;

// Simple hash for noise generation
float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// 2D value noise
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion — 4 octaves for paper grain
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 screen = texture(SCREEN_TEXTURE, uv);

	// Paper grain — subtle texture on bright areas
	float grain = fbm(uv * 350.0 + 42.0);
	grain = grain * 0.06 - 0.03;

	// Ink density from luminance
	float lum = dot(screen.rgb, vec3(0.299, 0.587, 0.114));
	float ink = 1.0 - lum;

	// Pressure darkens ink
	ink += pressure_level * 0.1;

	// Edge bleeding — animated
	float edge_noise = fbm(uv * 180.0 + time_value * 0.0005);
	ink += (edge_noise - 0.5) * 0.08;

	// Dry brush texture
	float dry = vnoise(uv * 120.0 + 17.0);
	ink *= smoothstep(0.03, 0.08, dry);

	// Brush stroke variation — animated
	float brush = fbm(uv * 60.0 + vec2(0.0, time_value * 0.001));
	ink += (brush - 0.5) * 0.12;

	// Three-tone ink wash: light → medium → deep
	vec3 ink_color = vec3(0.06, 0.05, 0.08);
	vec3 paper_color = vec3(0.96, 0.94, 0.89) + grain;

	float wash_light = smoothstep(0.15, 0.35, ink);
	float wash_medium = smoothstep(0.35, 0.55, ink);
	float wash_deep = smoothstep(0.55, 0.75, ink);

	vec3 wash_color = paper_color;
	wash_color = mix(wash_color, mix(paper_color, ink_color, 0.3), wash_light);
	wash_color = mix(wash_color, mix(ink_color, paper_color, 0.2), wash_medium);
	wash_color = mix(wash_color, ink_color, wash_deep * 0.9);

	// Ink pooling
	float pool = fbm(uv * 90.0 + 7.0);
	wash_color -= vec3(0.02) * wash_deep * pool;

	// Color from knowledge — restore original color based on knowledge_level
	float color_mask = smoothstep(0.25, 0.5, ink) * knowledge_level;
	wash_color = mix(wash_color, screen.rgb, color_mask * 0.65);

	// Desaturation — increases with knowledge
	float final_lum = dot(wash_color, vec3(0.299, 0.587, 0.114));
	float saturation = 0.2 + knowledge_level * 0.5;
	wash_color = mix(vec3(final_lum), wash_color, saturation);

	// Vignette — frame edges darken
	float vignette = 1.0 - length((uv - 0.5) * 1.4);
	vignette = smoothstep(0.0, 0.7, vignette);
	wash_color = mix(ink_color * 0.5 + paper_color * 0.5, wash_color, vignette);

	COLOR = vec4(wash_color, 1.0);
}
