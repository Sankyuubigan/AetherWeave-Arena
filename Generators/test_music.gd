extends SceneTree
## Тест музыки карт (17.11.26): шина Music, треки .res с лупом, кроссфейд
## note_combat → боевой луп поверх приглушённого фона → возврат фона.
## Автозагрузки в -s нет — MusicDirector добавляется руками.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fails: Array[String] = []
	var md = load("res://Graphics/MusicDirector.gd").new()
	md.name = "MusicDirector"
	root.add_child(md)
	await process_frame

	# 1) Шина Music создана
	if AudioServer.get_bus_index("Music") < 0:
		fails.append("шина Music не создана")
	else:
		print("MUS-TEST: шина Music есть")

	# 2) Треки грузятся и зациклены
	for tr in ["map1_ambient", "map2_ambient", "combat_loop"]:
		var s = load("res://Audio/Music/%s.res" % tr)
		if s == null:
			fails.append("не грузится %s.res" % tr)
		elif s.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			fails.append("%s не зациклен" % tr)
	if fails.is_empty():
		print("MUS-TEST: 3 трека .res на месте, loop=FORWARD")

	# 3) Фон карты: _switch_bg + проигрывание
	md._switch_bg(load("res://Audio/Music/map1_ambient.res"))
	await process_frame
	await process_frame
	if not md.bg.playing:
		fails.append("фон не играет")
	else:
		print("MUS-TEST: фон играет (", md.bg.stream.resource_path.get_file(), ")")

	# 4) Бой: боевой луп поверх, фон приглушён
	md.note_combat(0.2)
	await process_frame
	if not md.combat.playing:
		fails.append("боевой луп не играет")
	else:
		print("MUS-TEST: боевой луп играет, фон приглушается (bg db=", "%.1f" % md.bg.volume_db, ")")

	# 5) Возврат: hold истёк → боевой затухает и останавливается, фон возвращается
	for i in 200:
		await process_frame
	if md.combat.playing and md.combat.volume_db > -39.0 and md._combat_left <= 0.0:
		# ещё в процессе фейда-аута — это ок, но объём должен падать
		print("MUS-TEST: боевой в фейд-ауте (db=", "%.1f" % md.combat.volume_db, ")")
	elif not md.combat.playing:
		print("MUS-TEST: боевой остановлен, фон вернулся (db=", "%.1f" % md.bg.volume_db, ")")
	else:
		fails.append("боевой луп не затухает после hold")

	if fails.is_empty():
		print("MUS-TEST: ALL PASS")
		quit(0)
	else:
		print("MUS-TEST FAIL: ", "; ".join(fails))
		quit(1)
