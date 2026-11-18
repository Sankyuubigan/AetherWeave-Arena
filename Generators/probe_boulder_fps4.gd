extends SceneTree
## Зонд фриза v4 (19.11.26): АУДИО-ВЕТКА. v1–v3 чисты, но у зонда скрытое окно
## = нет фокуса = AudioManager глушит шины → Godot может не микшировать →
## аудио-столлы невоспроизводимы. Здесь: (1) снимаем мьют принудительно,
## (2) даём фону заиграть по-настоящему, (3) дёргаем note_combat() — боевой
## луп грузится СИНХРОННО в _process (в обычной сессии это первый удар; манекены
## у спавна, у валуна). Лог каждого кадра от нуля.
## Запуск: _tmp_probe/probe_boulder_fps4.ps1 (скрытое окно).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var arena: Node = (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	print("BF4 boot=%.0fms" % [(Time.get_ticks_usec() - t0) / 1000.0])

	var audio := root.get_node_or_null("/root/AudioManager")
	var music := root.get_node_or_null("/root/MusicDirector")

	# Фаза 1: первые 120 кадров как есть (фокус-мьют активен — как в v3)
	await _frames("P1-старт-мьют", 120)

	# Фаза 2: принудительный звук (имитация фокуса юзера)
	if audio:
		audio.set("_unfocused", false)
		audio._apply_all_buses()
		print("BF4 аудио включён принудительно")
	await _frames("P2-звук-вкл", 180)

	# Фаза 3: боевой луп (первое срабатывание = синхронный load в _process)
	if music:
		music.note_combat()
		print("BF4 note_combat вызван")
	await _frames("P3-боевой-луп", 180)

	# Фаза 4: повторный боевой (кеш уже прогрет)
	if music:
		music.note_combat()
	await _frames("P4-боевой-повтор", 120)
	quit(0)

func _frames(tag: String, n: int) -> void:
	var slow := 0
	var stall := 0.0
	var worst := 0.0
	for i in n:
		var f0 := Time.get_ticks_usec()
		await process_frame
		var ms := (Time.get_ticks_usec() - f0) / 1000.0
		if ms > 30.0:
			slow += 1
			stall += ms
			print("BF4 %s кадр %d: %.0fms" % [tag, i, ms])
		worst = maxf(worst, ms)
	print("BF4 %s: >30ms=%d, стыл=%.2fс, worst=%.1fms" % [tag, slow, stall / 1000.0, worst])
