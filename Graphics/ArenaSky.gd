extends RefCounted
class_name ArenaSky
## Небо арен (мастер-план 18.11.26, задача 1): один sky-шейдер на 3 карты,
## темы — наборы юниформов. Генераторы вызывают apply() после env-блока.
## Демо-источник: godot-demo-projects/3d/sky_shaders.

const SHADER_PATH := "res://Graphics/Sky/arena_sky.gdshader"

## Применить тему неба к Environment карты. Темы: "main", "forest", "hell".
static func apply(env: Environment, theme: StringName) -> void:
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var preset := _preset(theme)
	for k in preset:
		mat.set_shader_parameter(k, preset[k])
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME  # TIME-анимация облаков/эмберов
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	print("ArenaSky: тема неба «%s» применена" % theme)

## Пресеты тем (SSOT: юниформы только здесь, в шейдере только дефолты main).
static func _preset(theme: StringName) -> Dictionary:
	match theme:
		"hell":
			# Багровый апокалипсис: чёрный зенит, кровавый горизонт, тёмные
			# рваные тучи, восходящие эмберы, тусклое красное «солнце».
			return {
				"u_top": Color(0.03, 0.005, 0.005),
				"u_horizon": Color(0.36, 0.05, 0.02),
				"u_bottom": Color(0.08, 0.02, 0.01),
				"u_horizon_sharp": 2.2,
				"u_sun_color": Color(0.9, 0.25, 0.08),
				"u_sun_size": 0.02,
				"u_glow": 0.8,
				"u_cloud_color": Color(0.16, 0.05, 0.03),
				"u_cloud_cover": 0.5,
				"u_cloud_speed": 0.02,
				"u_cloud_dark": 0.75,
				"u_ember_color": Color(1.0, 0.42, 0.08),
				"u_ember_amount": 1.0,
			}
		"forest":
			# Свежее утро: зеленоватая мгла у горизонта, лёгкие облака.
			return {
				"u_top": Color(0.16, 0.34, 0.58),
				"u_horizon": Color(0.62, 0.72, 0.58),
				"u_bottom": Color(0.22, 0.26, 0.20),
				"u_horizon_sharp": 3.0,
				"u_sun_color": Color(1.0, 0.92, 0.72),
				"u_sun_size": 0.012,
				"u_glow": 0.3,
				"u_cloud_color": Color(0.88, 0.92, 0.88),
				"u_cloud_cover": 0.45,
				"u_cloud_speed": 0.006,
				"u_cloud_dark": 0.3,
				"u_ember_color": Color(1.0, 0.42, 0.08),
				"u_ember_amount": 0.0,
			}
		_:
			# main — тёплый день: голубой зенит, тёплая дымка у горизонта.
			return {
				"u_top": Color(0.13, 0.30, 0.62),
				"u_horizon": Color(0.83, 0.72, 0.55),
				"u_bottom": Color(0.28, 0.28, 0.26),
				"u_horizon_sharp": 3.0,
				"u_sun_color": Color(1.0, 0.86, 0.62),
				"u_sun_size": 0.012,
				"u_glow": 0.4,
				"u_cloud_color": Color(0.92, 0.92, 0.96),
				"u_cloud_cover": 0.38,
				"u_cloud_speed": 0.008,
				"u_cloud_dark": 0.25,
				"u_ember_color": Color(1.0, 0.42, 0.08),
				"u_ember_amount": 0.0,
			}
