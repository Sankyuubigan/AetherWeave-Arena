shader_type spatial;
// Мембрана нейро-портала (Q47): яркий магический вихрь-туманность + искры-звёзды,
// кайма по краю проёма. Референсы: tasks/261121_0458-bd2f1751/references/.
// base — VORTEX-шейдер PortalRing.gd (Q21/Q44), расширен: fbm-туманность, звёзды,
// маска проёма (круг для кольца B / стрельчатая готика для арки A), blend_add.
render_mode unshaded, cull_disabled, blend_add;

uniform vec4 color_a : source_color = vec4(0.42, 0.22, 0.95, 1.0); // туманность: фиолет
uniform vec4 color_b : source_color = vec4(0.10, 0.62, 1.0, 1.0);  // циан-синий
uniform vec4 color_core : source_color = vec4(0.85, 0.92, 1.0, 1.0); // яркие филаменты/ядро
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float speed : hint_range(0.0, 3.0) = 1.0;
uniform float seed_off = 0.0;
uniform float opaque_mode = 0.0; // LOW-графика: непрозрачная мембрана без discard-экономии
uniform int mask_type : hint_range(0, 1) = 0; // 0 = круг (кольцо B), 1 = стрельчатая готика (A)

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

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

float fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		s += amp * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return s;
}

// Стрельчатая готика: боковые пилястры + две дуги, сходящиеся в острую макушку.
// p в -1..1 по кваду; возвращает 0..1 покрытие (1 = внутри проёма).
float mask_gothic(vec2 p) {
	float half_w = 0.62;
	float d = 0.30;          // смещение центров дуг от оси
	float R = 0.92;          // радиус дуг
	float spring = -0.25;    // высота пят арки (старт дуг)
	float floor_y = -1.0;
	float inside_x = step(abs(p.x), half_w);
	// верхняя граница: две дуги с центрами x=±d на высоте spring
	float dx = abs(p.x) - d;
	float arc = spring + sqrt(max(0.0, R * R - dx * dx));
	float inside_y = step(p.y, max(arc, spring));
	float inside_floor = step(floor_y, p.y);
	return inside_x * inside_y * inside_floor;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0; // -1..1
	float m = 0.0;
	if (mask_type == 0) {
		m = step(length(p), 1.0);
	} else {
		m = mask_gothic(p);
	}
	if (m <= 0.002) {
		discard;
	}

	// Полярный вихрь: закрутка угла по радиусу + время
	float r = length(p);
	float ang = atan(p.y, p.x);
	float sw = ang + r * 2.6 - TIME * speed * 1.2 + seed_off;
	vec2 sp = vec2(cos(sw), sin(sw)) * r;

	// Туманность: два слоя fbm
	float n1 = fbm(sp * 3.0 + vec2(seed_off, -TIME * speed * 0.35));
	float n2 = fbm(sp * 6.5 - TIME * speed * 0.55);
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.25, 0.75, n1));
	col += color_core.rgb * pow(max(n2 - 0.30, 0.0) * 1.8, 2.0) * 1.1; // филаменты

	// Светящееся ядро-кольцо (как в рефах: яркое кольцо внутри)
	float ring_glow = exp(-pow((r - 0.55) * 4.0, 2.0)) * 0.75;
	col += color_core.rgb * ring_glow;

	// Кайма у края проёма
	col += color_b.rgb * (1.0 - m) * 1.6;

	// Искры-звёзды: сетка хэшей, мерцание
	vec2 gp = p * 7.0 + seed_off;
	vec2 gi = floor(gp);
	vec2 gf = fract(gp) - vec2(0.5);
	float star_sel = hash21(gi);
	float tw = 0.5 + 0.5 * sin(TIME * 3.0 * speed * (1.0 + star_sel) + star_sel * 43.0);
	float star = smoothstep(0.42, 0.0, length(gf)) * step(0.80, star_sel) * tw;
	col += vec3(1.0, 1.0, 0.95) * star * 1.8;

	float alpha = clamp(intensity * (0.34 + 0.66 * n1), 0.0, 1.0) * m;
	ALBEDO = col * intensity;
	ALPHA = mix(alpha, m, opaque_mode);
}
