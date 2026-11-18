extends SceneTree

## Тест QUEUE Q1/Q3/Q4: GraphicsQuality — VRS только в LOW, SDFGI только в
## HIGH, MEDIUM = базлайн карты (SSAO/туман не тронуты). Плюс персист секции
## [graphics] в user://settings.cfg. Гейт: GATE ALL PASS, иначе quit(1).

const GQScript = preload("res://Graphics/GraphicsQuality.gd")

var fails := 0

func _init() -> void:
	await process_frame
	_run()

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

func _run() -> void:
	# Сцена с WE (как MainArena: SSAO+туман) — ставим ДО GraphicsQuality._ready,
	# чтобы базлайн снялся со «свежего» env.
	var scene := Node3D.new()
	scene.name = "TestScene"
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	we.environment = env
	scene.add_child(we)
	root.add_child(scene)
	current_scene = scene # ПОСЛЕ add_child: сеттер -s-режима до входа в дерево не сработал

	var gq := GQScript.new()
	gq.name = "GraphicsQuality"
	root.add_child(gq) # _ready: _load_settings + node_added + _apply
	await process_frame

	_check("по умолчанию MEDIUM", gq.quality == GQScript.Quality.MEDIUM)
	_check("MEDIUM: SSAO остался", env.ssao_enabled)
	_check("MEDIUM: туман остался", env.volumetric_fog_enabled)
	_check("MEDIUM: SDFGI off", not env.sdfgi_enabled)
	_check("MEDIUM: VRS отключен", root.vrs_mode == Viewport.VRS_DISABLED)

	gq.set_quality(GQScript.Quality.LOW)
	await process_frame
	var found := gq._find_world_env()
	print("DBG we_found=", found, " same_as_test_we=", found == we, " q=", gq.quality,
		" ssao=", env.ssao_enabled, " we_env_is_same=", we.environment == env)
	_check("LOW: VRS_TEXTURE", root.vrs_mode == Viewport.VRS_TEXTURE)
	_check("LOW: vrs_texture назначена", root.vrs_texture != null)
	_check("LOW: SSAO off", not env.ssao_enabled)
	_check("LOW: туман off", not env.volumetric_fog_enabled)
	_check("LOW: SDFGI off", not env.sdfgi_enabled)

	gq.set_quality(2) # HIGH
	await process_frame
	_check("HIGH: SDFGI on", env.sdfgi_enabled)
	_check("HIGH: каскады 6", env.sdfgi_cascades == 6)
	_check("HIGH: occlusion SDFGI", env.sdfgi_use_occlusion)
	_check("HIGH: SSAO вернулся (базлайн)", env.ssao_enabled)
	_check("HIGH: туман вернулся (базлайн)", env.volumetric_fog_enabled)
	_check("HIGH: VRS отключен", root.vrs_mode == Viewport.VRS_DISABLED)

	# Персист: HIGH уже записан в settings.cfg set_quality'ем — свежий инстанс
	# должен прочитать то же значение.
	var gq2 := GQScript.new()
	root.add_child(gq2)
	await process_frame
	_check("персист: свежий инстанс читает HIGH", gq2.quality == 2)

	# Санитари-финал: вернуть MEDIUM — чистое состояние для юзера.
	gq.set_quality(GQScript.Quality.MEDIUM)
	_check("возврат в MEDIUM: SSAO, без SDFGI", env.ssao_enabled and not env.sdfgi_enabled)

	if fails == 0:
		print("GATE ALL PASS")
	else:
		print("GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
