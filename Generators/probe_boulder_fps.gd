extends SceneTree
## Зонд фриза у валуна MainArena (18.11.26, вердикт юзера: «рядом с ним 3 фпс»).
## Матрица изоляции причины — факты, не догадки (§1.9):
##   A: игрок РЯДОМ с валуном (5,0,-3)      — воспроизводится ли фриз зондом
##   B: игрок ДАЛЕКО (80,0,80)              — контроль
##   C: рядом + валун hidden                — рендер-стоимость камня?
##   D: рядом + SSAO/контакт-тени OFF       — пост-процесс на геометрии камня?
## Каждая фаза: до 150 кадров или 12 с, per-frame delta, RenderingServer-инфо.
## Запуск: _tmp_probe/probe_boulder_fps.ps1 (скрытое окно, GPU-рендер).

const MEAS_FRAMES := 150
const MEAS_TIME_CAP := 12.0

func _init() -> void:
	call_deferred("_run")

func _measure(tag: String) -> Dictionary:
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var worst_ms := 0.0
	while frames < MEAS_FRAMES and (Time.get_ticks_usec() - t0) < MEAS_TIME_CAP * 1_000_000.0:
		var f0 := Time.get_ticks_usec()
		await process_frame
		var ms := (Time.get_ticks_usec() - f0) / 1000.0
		if frames >= 5: # первые кадры после телепорта — прогрев/компиляция шейдеров
			worst_ms = maxf(worst_ms, ms)
		frames += 1
	var total_s := (Time.get_ticks_usec() - t0) / 1_000_000.0
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var res := {
		"fps": frames / total_s, "worst_ms": worst_ms,
		"dc": dc, "prims": prims, "vram_mb": vram / 1048576.0,
	}
	print("BFP %s: fps=%.1f worst=%.1fms DC=%d prims=%d VRAM=%.0fMB" % [
		tag, res.fps, res.worst_ms, dc, prims, res.vram_mb])
	return res

func _run() -> void:
	var arena = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(arena)
	for i in 30:
		await process_frame

	# Валун и игрок
	var boulder: Node3D = null
	var player: CharacterBody3D = null
	var stack: Array = [arena]
	while stack:
		var nd = stack.pop_front()
		if nd.name.begins_with("Boulder"):
			boulder = nd
		if nd is CharacterBody3D and nd.name == "Player":
			player = nd
		for c in nd.get_children():
			stack.append(c)
	if boulder == null or player == null:
		print("BFP FAIL: boulder=", boulder, " player=", player)
		quit(1)
		return
	var bpos: Vector3 = boulder.global_position
	print("BFP валун в ", bpos, ", AABB-габариты смотрим по мешу")

	# WorldEnvironment/свет — для фазы D
	var we: WorldEnvironment = null
	var sun: DirectionalLight3D = null
	stack = [arena]
	while stack:
		var nd = stack.pop_front()
		if nd is WorldEnvironment:
			we = nd
		if nd is DirectionalLight3D:
			sun = nd
		for c in nd.get_children():
			stack.append(c)

	# --- Фаза A: рядом, лицом к валуну
	player.global_position = bpos + Vector3(0, 0.6, 2.5)
	player.look_at(bpos + Vector3(0, 0.8, 0))
	for i in 10:
		await process_frame
	var ra := await _measure("A рядом")

	# --- Фаза B: далеко
	player.global_position = Vector3(80, 1.0, 80)
	for i in 10:
		await process_frame
	var rb := await _measure("B далеко")

	# --- Фаза C: рядом + валун скрыт (рендер-стоимость камня)
	player.global_position = bpos + Vector3(0, 0.6, 2.5)
	player.look_at(bpos + Vector3(0, 0.8, 0))
	boulder.visible = false
	for i in 10:
		await process_frame
	var rc := await _measure("C рядом+скрыт")
	boulder.visible = true

	# --- Фаза D: рядом + SSAO/контакт-тени OFF (пост-процесс?)
	if we and we.environment:
		we.environment.ssao_enabled = false
	if sun:
		sun.shadow_contact_shadows_allow = false
	for i in 10:
		await process_frame
	var rd := await _measure("D рядом+SSAO-выкл")

	# --- Вывод
	print("BFP РАЗНИЦА A→C (рендер камня): %.1f → %.1f fps" % [ra.fps, rc.fps])
	print("BFP РАЗНИЦА A→D (SSAO/контакт): %.1f → %.1f fps" % [ra.fps, rd.fps])
	print("BFP РАЗНИЦА A→B (расстояние):   %.1f → %.1f fps" % [ra.fps, rb.fps])
	quit(0)
