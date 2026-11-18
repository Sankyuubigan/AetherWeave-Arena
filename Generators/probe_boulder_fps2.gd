extends SceneTree
## Зонд фриза у валуна v2 (19.11.26): v1 (телепорт+прогрев) фриз НЕ поймал —
## спайк прятался в прогревочных кадрах. Здесь лог КАЖДОГО кадра и фазы
## «первого взгляда»:
##   P1: смотрим В СТОРОНУ (валун за спиной)   — базлайн
##   P2: поворот К валуну (первое появление)   — ожидаемый спайк (PSO/аплоад)
##   P3: отвод взгляда + ПОВТОРНЫЙ взгляд      — спайк повторяется?
##   P4: телепорт ближе с валуном в кадре      — мипы/LOD-переход
## Запуск: _tmp_probe/probe_boulder_fps2.ps1 (скрытое окно, GPU-рендер).

const LOG_EVERY := 1

func _init() -> void:
	call_deferred("_run")

func _find(arena: Node, nm: String) -> Node3D:
	var st: Array = [arena]
	while st:
		var nd = st.pop_front()
		if nd.name.begins_with(nm):
			return nd
		for c in nd.get_children():
			st.append(c)
	return null

func _log(tag: String, i: int, ms: float, cam: Camera3D, bpos: Vector3, player: CharacterBody3D) -> void:
	var fr := cam.is_position_in_frustum(bpos + Vector3(0, 0.8, 0))
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("BF2 %s f=%d ms=%.2f frust=%d dc=%d dist=%.1f" % [
		tag, i, ms, 1 if fr else 0, dc, player.global_position.distance_to(bpos)])

func _phase(tag: String, frames: int, player: CharacterBody3D, cam: Camera3D, bpos: Vector3) -> float:
	var worst := 0.0
	for i in frames:
		var f0 := Time.get_ticks_usec()
		await process_frame
		var ms := (Time.get_ticks_usec() - f0) / 1000.0
		worst = maxf(worst, ms)
		if i % LOG_EVERY == 0 or ms > 50.0:
			_log(tag, i, ms, cam, bpos, player)
	print("BF2 %s WORST=%.1fms" % [tag, worst])
	return worst

func _run() -> void:
	var arena: Node = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(arena)
	for i in 30:
		await process_frame
	var boulder := _find(arena, "Boulder")
	var player := _find(arena, "Player")
	if boulder == null or player == null:
		print("BF2 FAIL")
		quit(1)
		return
	var bpos: Vector3 = boulder.global_position
	var cam: Camera3D = _find(player, "Camera")
	if cam == null:
		var st: Array = [player]
		while st:
			var nd = st.pop_front()
			if nd is Camera3D:
				cam = nd
				break
			for c in nd.get_children():
				st.append(c)
	print("BF2 валун=%s игрок=%s камера=%s" % [bpos, player.global_position, cam])

	# P1: смотрим в сторону, валун за спиной
	player.global_position = Vector3(5, 0.6, 20)
	player.look_at(Vector3(5, 0.6, 60))
	for i in 20:
		await process_frame
	await _phase("P1-спиной", 40, player, cam, bpos)

	# P2: первый взгляд на валун
	player.look_at(bpos + Vector3(0, 0.8, 0))
	await _phase("P2-первый-взгляд", 90, player, cam, bpos)

	# P3: отвод + повторный взгляд
	player.look_at(Vector3(5, 0.6, 60))
	for i in 20:
		await process_frame
	player.look_at(bpos + Vector3(0, 0.8, 0))
	await _phase("P3-повторный", 90, player, cam, bpos)

	# P4: телепорт ближе, валун остаётся в кадре
	player.global_position = bpos + Vector3(0, 0.6, 2.5)
	player.look_at(bpos + Vector3(0, 0.8, 0))
	await _phase("P4-рядом", 60, player, cam, bpos)
	quit(0)
