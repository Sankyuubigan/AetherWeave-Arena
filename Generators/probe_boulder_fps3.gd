extends SceneTree
## Зонд фриза v3 (19.11.26): СТАРТОВОЕ окно. Спавн игрока (0,1,0) в 6 м от
## валуна (5,0,-3) — «фриз у валуна» = фриз первых секунд забега. v1/v2 его
## пропускали: меряли ПОСЛЕ 20–30 прогревочных кадров. Здесь замер от нуля:
## время load/instantiate/первый кадр + лог КАЖДОГО кадра (медленные — всегда).
## Запуск: _tmp_probe/probe_boulder_fps3.ps1 (скрытое окно, GPU-рендер).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var packed: PackedScene = load("res://Scenes/MainArena.tscn")
	var t_load := Time.get_ticks_usec()
	var arena: Node = packed.instantiate()
	var t_inst := Time.get_ticks_usec()
	root.add_child(arena)
	var t_add := Time.get_ticks_usec()
	print("BF3 load=%.0fms instantiate=%.0fms add_child=%.0fms" % [
		(t_load - t0) / 1000.0, (t_inst - t_load) / 1000.0, (t_add - t_inst) / 1000.0])

	var slow30 := 0
	var slow100 := 0
	var stall_us := 0
	var first_ok_frame := -1
	var n := 600
	for i in n:
		var f0 := Time.get_ticks_usec()
		await process_frame
		var ms := (Time.get_ticks_usec() - f0) / 1000.0
		if ms > 30.0:
			slow30 += 1
			stall_us += int((Time.get_ticks_usec() - f0))
			print("BF3 КАДР %d: %.0fms" % [i, ms])
		if ms > 100.0:
			slow100 += 1
		if ms < 30.0 and first_ok_frame < 0:
			first_ok_frame = i
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	print("BF3 ИТОГ: кадров>30ms=%d, >100ms=%d, суммарный стыл=%.2fс, первый лёгкий кадр=%d, VRAM=%.0fMB" % [
		slow30, slow100, stall_us / 1_000_000.0, first_ok_frame, vram / 1048576.0])
	quit(0)
