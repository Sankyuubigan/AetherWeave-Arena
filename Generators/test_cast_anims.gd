extends SceneTree
## Функциональный тест каст-анимаций (архитектура «всегда UB», 17.11.26):
## все UB-касты доступны has_cast_anim, играют на CastPlayer (верх тела),
## локомоция на основном плеере живёт под кастом, канал Enter→Loop→Shoot.

const NAMES := ["Cast_Enter", "Cast_Loop", "Cast_Shoot", "Cast_Shoot_L",
	"Cast_Exit", "Throw", "Heart_Cast", "Heart_Cast_L", "Spell_Cast", "Spell_Cast_L",
	"Cast_1H_Magic_01"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	if ps == null:
		print("CAST-TEST FAIL: нет player.tscn")
		quit(1)
		return
	var player = ps.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if comp == null:
		print("CAST-TEST FAIL: нет PlayerAnimationComponent")
		quit(1)
		return
	var fails: Array[String] = []

	# 1) Имена: логическое имя → <Имя>_UB на CastPlayer
	var missing: Array[String] = []
	for n in NAMES:
		if not comp.has_cast_anim(n):
			missing.append(n)
	if missing.size() > 0:
		fails.append("нет UB-вариантов: " + ", ".join(missing))
	else:
		print("CAST-TEST: все ", NAMES.size(), " каст-имён доступны (UB)")

	# 2) Инвариант (уточнён 26.11.26): в библиотеке CastPlayer теперь лежат И
	#    UB-клипы, И full-body (их играет play_full_body стоя). Инвариант «только
	#    ротации» верен для UB; у full-body законна ПОЗИЦИЯ Hips (присед/наклон),
	#    но не позиция других костей и не Hips-трек в UB.
	var ub_pos := 0      # не-ротационные треки в UB-клипах (должно быть 0)
	var fb_bad := 0     # не-Hips не-ротационные треки в full-body (должно быть 0)
	var clib = comp.cast_player.get_animation_library("")
	for an in clib.get_animation_list():
		var a: Animation = clib.get_animation(an)
		var is_ub := String(an).ends_with("_UB")
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(a.track_get_path(i)).substr(String(a.track_get_path(i)).rfind(":") + 1)
			if is_ub:
				ub_pos += 1
			elif bone != "mixamorig_Hips":
				fb_bad += 1
	if ub_pos > 0 or fb_bad > 0:
		fails.append("не-ротационные треки: в UB %d, в full-body чужих %d" % [ub_pos, fb_bad])
	else:
		print("CAST-TEST: инвариант — UB только ротации, full-body только позиция Hips")

	# 3) Инста-каст: играет на CastPlayer, локомоция (дерево) живёт
	comp.play_cast_anim("Throw")
	for i in 5:
		await process_frame
	var cur: String = comp.cast_player.current_animation
	if cur != "Throw_UB":
		fails.append("после Throw на CastPlayer: " + cur)
	elif not comp.cast_player.is_playing():
		fails.append("Throw_UB не играет")
	elif comp.loco_state() == "":
		fails.append("локомоция замерла под кастом (дерево не стартовало)")
	elif comp.playback == null or String(comp.playback.get_current_node()) == "":
		fails.append("playback дерева пуст")
	else:
		print("CAST-TEST: Throw → ", cur, " на CastPlayer; локомоция живёт (",
			comp.loco_state(), "/", comp.playback.get_current_node(), ")")

	# 4) Канал: Enter → Loop (ждём с дедлайном — тайминг headless плавает)
	comp.play_channel()
	var waited := 0
	while comp.cast_player.current_animation != "Cast_Loop_UB" and waited < 180:
		await process_frame
		waited += 1
	var chan_cur: String = comp.cast_player.current_animation
	if not comp.is_channeling():
		fails.append("канал не активен")
	elif chan_cur != "Cast_Loop_UB":
		fails.append("канал за %d кадров: %s (ожидался Cast_Loop_UB)" % [waited, chan_cur])
	else:
		print("CAST-TEST: канал Enter→Loop OK (за ", waited, " кадров), is_channeling=true")
	comp.end_channel()
	await process_frame
	var end_cur: String = comp.cast_player.current_animation
	if end_cur != "Cast_Shoot_UB":
		fails.append("после end_channel: " + end_cur)
	else:
		print("CAST-TEST: end_channel → Cast_Shoot_UB")

	# 5) Спам: повторное нажатие ДОЛЖЕН рестартовать клип, другое имя —
	# перебить (баг 17.11.26: play() на играющем клипе не рестартует —
	# «прошлая анимация не отменяется»; фикс = stop() перед play+capture).
	comp.play_cast_anim("Throw")
	var w1 := 0
	while comp.cast_player.current_animation_position < 0.20 and w1 < 600:
		await process_frame
		w1 += 1
	var spam_before: float = comp.cast_player.current_animation_position
	comp.play_cast_anim("Throw")
	for i in 3:
		await process_frame
	var spam_after: float = comp.cast_player.current_animation_position
	if spam_after >= spam_before * 0.5:
		fails.append("спам не рестартует Throw: %.3f→%.3f" % [spam_before, spam_after])
	else:
		print("CAST-TEST: спам рестартует Throw (%.3f→%.3f)" % [spam_before, spam_after])
	# Другой скилл посреди каста — перебивает
	comp.play_cast_anim("Heart_Cast")
	for i in 3:
		await process_frame
	var switch_cur: String = comp.cast_player.current_animation
	if switch_cur != "Heart_Cast_UB":
		fails.append("перебивание другим скиллом: " + switch_cur)
	else:
		print("CAST-TEST: Throw перебит Heart_Cast (", switch_cur, ")")

	# 6) Дерево локомоции (17.11.26): travel + производные клипы. FSM компонента
	# спим — в голой сцене игрок падает, физика дёргала бы travel.
	comp.set_process(false)
	if not comp.anim_player.has_animation("Jump_Launch"):
		fails.append("нет производного Jump_Launch")
	elif not comp.anim_player.has_animation("FrontFlip_Fast"):
		fails.append("нет производного FrontFlip_Fast")
	else:
		var jl: Animation = comp.anim_player.get_animation("Jump_Launch")
		var ff: Animation = comp.anim_player.get_animation("FrontFlip_Fast")
		var flip: Animation = comp.anim_player.get_animation("FrontFlip")
		var lc: Animation = comp.anim_player.get_animation("Landing_Cut")
		print("CAST-TEST: Jump_Launch ", snappedf(jl.length, 0.01), "с (ожидалось ~0.42, взлёт), ",
			"FrontFlip_Fast ", snappedf(ff.length, 0.01), "с (из ", snappedf(flip.length, 0.01), "с), ",
			"Landing_Cut ", snappedf(lc.length, 0.01), "с (ожидалось ~0.60, удар+вставание)")
		if absf(jl.length - 0.42) > 0.05:
			fails.append("Jump_Launch длина %.2f (ожидалось ~0.42)" % jl.length)
		if absf(lc.length - 0.60) > 0.05:
			fails.append("Landing_Cut длина %.2f (ожидалось ~0.60)" % lc.length)
	comp._travel("Run")
	# travel() отложенный — фейд материализуется на следующем кадре (зонд:
	# чтение fading в том же кадре даёт пусто и ложно «дерево не пришло»)
	await process_frame
	var w2 := 0
	while String(comp.playback.get_fading_from_node()) != "" and w2 < 300:
		await process_frame
		w2 += 1
	if String(comp.playback.get_current_node()) != "Run":
		fails.append("дерево не пришло в Run: " + String(comp.playback.get_current_node()))
	else:
		print("CAST-TEST: дерево — travel Run OK (фейд ", w2, " кадров)")
	comp._travel("Idle")
	await process_frame
	w2 = 0
	while String(comp.playback.get_fading_from_node()) != "" and w2 < 300:
		await process_frame
		w2 += 1
	if String(comp.playback.get_current_node()) != "Idle":
		fails.append("дерево не вернулось в Idle: " + String(comp.playback.get_current_node()))
	else:
		print("CAST-TEST: дерево — travel Idle OK")
	comp.set_process(true)

	if fails.is_empty():
		print("CAST-TEST: ALL PASS")
		quit(0)
	else:
		print("CAST-TEST FAIL: ", "; ".join(fails))
		quit(1)
