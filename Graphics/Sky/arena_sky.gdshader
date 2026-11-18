shader_type sky;
render_mode use_debanding;

// Небо арен (мастер-план 18.11.26, задача 1): ОДИН шейдер на 3 карты,
// темы задаются юниформами из Graphics/ArenaSky.gd (main / forest / hell).
// Солнце и глоу привязаны к LIGHT0_* — следят за DirectionalLight3D карты.

group_uniforms palette;
uniform vec3 u_top : source_color = vec3(0.13, 0.30, 0.62);
uniform vec3 u_horizon : source_color = vec3(0.83, 0.72, 0.55);
uniform vec3 u_bottom : source_color = vec3(0.28, 0.28, 0.26);
uniform float u_horizon_sharp : hint_range(0.5, 8.0) = 3.0;

group_uniforms sun;
uniform vec3 u_sun_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float u_sun_size : hint_range(0.0, 0.2) = 0.012;
uniform float u_glow : hint_range(0.0, 2.0) = 0.4;

group_uniforms clouds;
uniform vec3 u_cloud_color : source_color = vec3(0.92, 0.92, 0.96);
uniform float u_cloud_cover : hint_range(0.0, 1.0) = 0.38;
uniform float u_cloud_speed : hint_range(0.0, 0.2) = 0.008;
uniform float u_cloud_dark : hint_range(0.0, 1.0) = 0.25;

group_uniforms embers;
uniform vec3 u_ember_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float u_ember_amount : hint_range(0.0, 1.0) = 0.0;

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
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	// Вертикальный градиент: зенит → горизонт, ниже горизонта — подцветка.
	float t = pow(clamp(1.0 - abs(dir.y), 0.0, 1.0), u_horizon_sharp);
	vec3 col = mix(u_top, u_horizon, t);
	if (dir.y < 0.0) {
		col = mix(col, u_bottom, clamp(-dir.y * 2.0, 0.0, 1.0));
	}
	// Солнце: диск + двойной глоу по направлению первого DirectionalLight.
	float sd = dot(dir, LIGHT0_DIRECTION);
	float disc = smoothstep(1.0 - u_sun_size * 1.4, 1.0 - u_sun_size, sd);
	float glow = pow(max(sd, 0.0), 64.0) * u_glow + pow(max(sd, 0.0), 8.0) * u_glow * 0.25;
	col += u_sun_color * (disc * 2.0 + glow) * LIGHT0_ENERGY;
	// Облака: fbm на плоскости над головой, скролл по TIME. Деление зажато
	// (max dir.y) и фейд от горизонта — иначе у зенита/горизонта рвутся в полосы.
	if (dir.y > 0.02 && u_cloud_cover > 0.001) {
		vec2 uv = dir.xz / max(dir.y, 0.15) * 1.4 + vec2(TIME * u_cloud_speed, TIME * u_cloud_speed * 0.6);
		float n = fbm(uv * 1.6);
		float cl = smoothstep(1.0 - u_cloud_cover, 1.0 - u_cloud_cover * 0.2, n);
		vec3 cc = mix(u_cloud_color * (1.0 - u_cloud_dark * fbm(uv * 3.0 + 3.7)), u_cloud_color, 0.7);
		col = mix(col, cc, cl * smoothstep(0.04, 0.18, dir.y));
	}
	// Эмберы (тема hell): восходящие оранжевые искры — два слоя шума со встречным скроллом.
	if (u_ember_amount > 0.001 && dir.y > -0.1) {
		vec2 ep = dir.xz / max(abs(dir.y) + 0.25, 0.25);
		float e1 = fbm(ep * 6.0 + vec2(0.0, -TIME * 0.25));
		float e2 = fbm(ep * 11.0 + vec2(TIME * 0.1, -TIME * 0.5));
		float sparks = smoothstep(0.75, 0.9, e1 * 0.6 + e2 * 0.5);
		col += u_ember_color * sparks * u_ember_amount * 1.5 * clamp(dir.y + 0.3, 0.0, 1.0);
	}
	COLOR = col;
}
