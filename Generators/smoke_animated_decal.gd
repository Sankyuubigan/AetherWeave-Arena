extends SceneTree
## Смоук анимированных декалей (4.8 DrawableTexture2D) — синхронный, -s-безопасный.
##
## Ловушки -s-режима (учтены, уроки handoff):
## - class_name-кэш не пересканируется → ссылки только через preload-консты;
## - в _init узлы ещё не «в дереве» → тело смоука через call_deferred;
## - process_frame в -s не тикает → _process(delta) вызываем руками;
##   tween-ы не продвигаются → проверяем СТАРТ фейда, не queue_free.
##
## Headless: рендер-сервер dummy — ловим именно ОШИБКИ КОДА, не картинку.

const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []

	# 1. Все генераторы кадров: пустые/битые кадры = фейл.
	var t0 := Time.get_ticks_msec()
	var generators := {
		"beam_scorch": DecalFrames.beam_scorch(Color(0.9, 0.3, 0.1)),
		"explosion_scorch": DecalFrames.explosion_scorch(Color(1.0, 0.45, 0.1)),
		"electric_scorch": DecalFrames.electric_scorch(Color(0.3, 0.85, 1.0)),
		"smoke_heal": DecalFrames.heal_pulse(Color(1.0, 0.5, 0.65)),
		"shockwave_ring": DecalFrames.shockwave_ring(Color(1.0, 0.9, 0.5)),
		"warp_in": DecalFrames.warp_ring(Color(0.55, 0.35, 1.0), true),
		"warp_out": DecalFrames.warp_ring(Color(0.55, 0.35, 1.0), false),
	}
	print("[SMOKE-DECAL] генераторы: %d мс, ключей: %d" % [Time.get_ticks_msec() - t0, generators.size()])
	for gname in generators:
		var frames: Array[Image] = generators[gname]
		if frames.is_empty():
			failures.append(gname + ": 0 кадров")
			continue
		var img: Image = frames[0]
		if img.get_width() != 64 or img.get_height() != 64:
			failures.append(gname + ": неверный размер кадра")
	# Sanity: у первого кадра beam есть непрозрачный пиксель в центре.
	var beam_img: Image = generators["beam_scorch"][0]
	var center_a: float = beam_img.get_pixel(32, 32).a
	if center_a < 0.5:
		failures.append("beam_scorch: центр кадra прозрачный (a=%.2f)" % center_a)

	# 2. Спавн декали в дерево (holder в корне — нужен для global_transform).
	var holder := Node3D.new()
	root.add_child(holder)
	var decal := AnimatedDecalComponent.new()
	decal.configure(generators["explosion_scorch"], 30.0, 0.25, 1.6)
	holder.add_child(decal)
	decal.place(Vector3.ZERO, Vector3.UP)
	if not is_instance_valid(decal):
		failures.append("spawn вернул невалидную декаль")
	else:
		if decal.texture_albedo == null:
			failures.append("texture_albedo не назначен (DrawableTexture2D?)")
		if decal.get_parent() != holder:
			failures.append("декаль не добавлена в parent")
		# Ручной прогон анимации: 10 тиков по 50 мс = 0.5 с (анимация 12 кадров
		# @30fps = 0.4с, lifetime 0.25 → фейд должен СТАРТОВАТЬ).
		var fade_started := false
		for i in 10:
			if not is_instance_valid(decal):
				break
			decal._process(0.05)
			if decal._fading:
				fade_started = true
				break
		if not fade_started:
			failures.append("фейд не стартовал за 0.5 с (lifetime 0.25)")

	if failures.is_empty():
		print("[SMOKE-DECAL] PASS: 7 генераторов, спавн+конфиг+place, анимация, старт фейда — ок")
	else:
		for f in failures:
			print("[SMOKE-DECAL] FAIL: ", f)
	quit(0 if failures.is_empty() else 1)
