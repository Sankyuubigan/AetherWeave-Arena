extends SceneTree

## Гейт вердикта 11-ответа: фикс купола в РЕАЛЬНОЙ сцене с физикой.
## Урок отчёта №3: probe_bard_vfx/render_bard_check ставили игрока на y=0
## без физики → «пробы зелёные, в рантайме криво». Здесь MainArena как есть:
## player.y покоя = 1.0 (капсула h=2.0 в origin), пол FloorBacking Y=0.0.
## Ассерты вердикта (Блок 1 §5):
##   abs(_mesh.global_position.y − 0.95) < 0.05   (центр купола = feet+0.95)
##   abs(_ring.global_position.y − 0.02) < 0.05   (кольцо на полу ground+0.02)
##   u_floor_y ≤ 0.22                             (ground+0.18)
##   кольцо скрыто в прыжке (dy ≥ R−0.1) и возвращается при посадке.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== PROBE: купол в реальной сцене (вердикт 11-ответа) ===")
	var scene = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(scene)
	# 2.0 с стеночного времени — физика обязана уложить игрока на пол.
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 2000000:
		await process_frame
	var player := _find_body(scene)
	if player == null:
		print("FAIL: CharacterBody3D не найден")
		quit(1)
		return
	var ok := true
	var flow = player.get_node_or_null("BardFlowComponent")
	var vfx = player.get_node_or_null("AcousticBarrierVFX")
	var stance = player.get_node_or_null("StanceComponent")
	if vfx == null or flow == null or stance == null:
		print("FAIL: нет AcousticBarrierVFX/BardFlowComponent/StanceComponent —",
				" PlayerController._ready не добрался")
		quit(1)
		return

	# ── 1. Кеш ног из коллайдера ──────────────────────────────────────────────
	var feet_off: float = vfx._feet_local_y
	if is_inf(feet_off):
		vfx._cache_feet(player)
		feet_off = vfx._feet_local_y
	ok = _chk(ok, absf(feet_off - (-1.0)) < 0.001,
			"кеш ног: _feet_local_y=%.3f (капсула h2.0 в origin → −1.0)" % feet_off)

	# ── 2. Включаем Поток в реальной сцене ────────────────────────────────────
	var cfg := {
		"stance_id": "bard_flow",
		"stance_skill_id": "bard_flow",
		"duration": 99.0,
		"sub_skills": [
			{"id": "bard_note", "default_slot": "ЛКМ"},
			{"id": "bard_chord", "default_slot": "ПКМ"},
			{"id": "bard_drop", "default_slot": "self"},
		],
		"sub_kinds": {"bard_note": "harmony", "bard_chord": "chord", "bard_drop": ""},
		"rhythm_gate": true,
	}
	var entered: bool = stance.enter_stance(cfg)
	ok = _chk(ok, entered, "вход в bard_flow через StanceComponent")
	ok = _chk(ok, flow.is_flowing, "BardFlowComponent.is_flowing = true")
	# VFX виден и посчитал геометрию (несколько кадров _process).
	var t1 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t1 < 300000:
		await process_frame
	ok = _chk(ok, vfx.visible, "AcousticBarrierVFX.visible (flowing)")
	ok = _chk(ok, vfx._feet_local_y == -1.0,
			"feet offset применён: _feet_local_y = %.3f" % vfx._feet_local_y)

	# ── 3. Ассерты вердикта: купол в мире ─────────────────────────────────────
	var mesh_y: float = vfx._mesh.global_position.y
	var ring_y: float = vfx._ring.global_position.y
	var floor_y: float = float(vfx._mat.get_shader_parameter("u_floor_y"))
	ok = _chk(ok, absf(mesh_y - 0.95) < 0.05,
			"купол центр Y = %.4f (ассерт |y−0.95|<0.05, feet 0.0 + 0.95)" % mesh_y)
	ok = _chk(ok, absf(ring_y - 0.02) < 0.05,
			"кольцо Y = %.4f (ассерт |y−0.02|<0.05, ground 0.0 + 0.02)" % ring_y)
	ok = _chk(ok, floor_y <= 0.22,
			"u_floor_y = %.4f (≤ 0.22 = ground+0.18)" % floor_y)
	ok = _chk(ok, absf(vfx._ring.scale.y - 0.15) < 0.05,
			"кольцо сплющено scale.y = %.3f (0.15)" % vfx._ring.scale.y)
	ok = _chk(ok, absf(vfx._ring.scale.x - 1.0) < 0.05,
			"кольцо радиус сечения scale.x = %.4f (dy=0.95 → 1.0 база)" % vfx._ring.scale.x)
	ok = _chk(ok, vfx._ring.visible, "кольцо видно на полу")

	# ── 4. Прыжок: кольцо скрыто, купол едет с ногами ─────────────────────────
	var t2 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t2 < 1500000:
		await process_frame
		player.global_position.y = 4.0  # удерживаем в воздухе против гравитации
	# физика гасит velocity, но позицию держим каждый кадр
	var t3 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t3 < 300000:
		await process_frame
		player.global_position.y = 4.0
	var mesh_y2: float = vfx._mesh.global_position.y
	var floor_y2: float = float(vfx._mat.get_shader_parameter("u_floor_y"))
	ok = _chk(ok, absf(mesh_y2 - 3.95) < 0.1,
			"прыжок: купол уехал с ногами (центр %.3f ≈ 4.0−1+0.95)" % mesh_y2)
	ok = _chk(ok, not vfx._ring.visible,
			"прыжок: кольцо скрыто (dy = %.2f ≥ R−0.1 = 1.8)" % (mesh_y2 - 0.95))
	ok = _chk(ok, floor_y2 <= 0.22,
			"прыжок: u_floor_y остался %.4f (raycast мимо → последний пол)" % floor_y2)

	# ── 5. Посадка: кольцо возвращается на пол ────────────────────────────────
	var t4 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t4 < 1500000:
		await process_frame
		player.global_position.y = 1.0
		player.velocity = Vector3.ZERO
	var t5 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t5 < 300000:
		await process_frame
	ok = _chk(ok, vfx._ring.visible, "посадка: кольцо вернулось на пол")
	var ring_y2: float = vfx._ring.global_position.y
	ok = _chk(ok, absf(ring_y2 - 0.02) < 0.05,
			"посадка: кольцо Y = %.4f (ground+0.02)" % ring_y2)

	# ── 6. Уборка: закрываем стойку корректно ─────────────────────────────────
	stance.exit_stance("cancel")
	# Переход is_flowing true→false виден в VFX._process ТОЛЬКО через кадр
	# (handoff раунда 3: баннер/видимость = переход, не мгновенный стейт).
	var t6 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t6 < 200000:
		await process_frame
	ok = _chk(ok, not flow.is_flowing, "выход cancel: is_flowing=false")
	ok = _chk(ok, not vfx.visible, "VFX скрылся после выхода")

	print("DOME_REAL_SCENE DONE: %s" % ("ALL PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _chk(ok: bool, cond: bool, what: String) -> bool:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		return false
	return ok

func _find_body(n: Node) -> Node:
	if n is CharacterBody3D:
		return n
	for c in n.get_children():
		var r := _find_body(c)
		if r != null:
			return r
	return null
