extends SceneTree

## Probe Q16 раунд 3 (вердикт спеца 09-ответ В.1): RhythmJudge — синхронное
## судейство (submit_press_at возвращает вердикт СРАЗУ), окна Perfect
## −55..+70 мс / Good −110..+130 мс (границы ±1 мс), пресс СТРОГО своего
## kind (чужая дорожка не трогается), empty_press с анти-дребезгом 0.18 с,
## пропуск ноты → Miss, фокус-аут без Miss. EXIT 0 = PASS.

const COND := preload("res://Logic/RhythmConductor.gd")
const JUDGE := preload("res://Logic/RhythmJudge.gd")

var _pass := 0
var _fail := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)

func _init() -> void:
	call_deferred("_run")

func _wait(cond, target: float) -> void:
	var guard := 0
	while cond.song_time < target and guard < 30000:
		guard += 1
		await process_frame

func _count(verdicts: Array, id: int) -> int:
	var c := 0
	for v in verdicts:
		if v[0] == id:
			c += 1
	return c

func _verdict_of(verdicts: Array, id: int) -> String:
	for v in verdicts:
		if v[0] == id:
			return str(v[1])
	return ""

func _run() -> void:
	print("=== PROBE: Q16 раунд 3 — RhythmJudge (В.1) ===")
	await process_frame
	var sc = load("res://Logic/RhythmJudge.gd")
	_ck(sc != null and sc.can_instantiate(), "парс RhythmJudge.gd")

	var cond = COND.new()
	var judge = JUDGE.new()
	root.add_child(cond)
	root.add_child(judge)
	await process_frame
	judge.conductor = cond
	cond.start(120.0)

	var verdicts := []       # [id, verdict, kind]
	var empties := []        # kind каждого empty_press
	var presses := []        # kind каждого press_received
	judge.note_judged.connect(func(id, v, k): verdicts.append([id, v, k]))
	judge.empty_press.connect(func(k): empties.append(k))
	judge.press_received.connect(func(k): presses.append(k))

	# Ноты на сетке 120 BPM (0.5 с)
	var n1 := judge.register_note("harmony", 3.0)
	var n2 := judge.register_note("harmony", 3.5)
	var n3 := judge.register_note("harmony", 4.0)
	var n4 := judge.register_note("harmony", 4.5)
	var n5 := judge.register_note("harmony", 5.0)
	var n5b := judge.register_note("harmony", 5.5)
	var n6 := judge.register_note("harmony", 6.0)
	var n7 := judge.register_note("harmony", 7.0)
	var c1 := judge.register_note("chord", 8.0)
	var n8 := judge.register_note("harmony", 9.0)
	var n9 := judge.register_note("harmony", 11.0)
	_ck(judge._next_id == 11, "регистрация нот: монотонные note_id")

	# 1) Границы окон ±1 мс + синхронный вердикт
	await _wait(cond, 2.8)
	var v: String = judge.submit_press_at(3.0 - 0.055, "harmony")
	_ck(v == "perfect", "submit_press_at вернул «perfect» СРАЗУ (sync-семантика)")
	_ck(_verdict_of(verdicts, n1) == "perfect" and str(verdicts[0][2]) == "harmony",
			"−55 мс → perfect (ранняя граница), сигнал несёт kind")
	_ck(presses.size() == 1, "press_received на каждый пресс")

	judge.submit_press_at(3.0, "harmony")
	await process_frame
	_ck(_count(verdicts, n1) == 1, "второй клик по той же ноте игнорируется (≤1 оценки)")

	await _wait(cond, 3.2)
	_ck(judge.submit_press_at(3.5 - 0.056, "harmony") == "good",
			"−56 мс → good (вне Perfect, внутри Good)")

	await _wait(cond, 3.7)
	_ck(judge.submit_press_at(4.0 + 0.070, "harmony") == "perfect",
			"+70 мс → perfect (поздняя граница, EPS-гард)")

	await _wait(cond, 4.2)
	_ck(judge.submit_press_at(4.5 + 0.071, "harmony") == "good", "+71 мс → good")

	await _wait(cond, 4.7)
	_ck(judge.submit_press_at(5.0 - 0.110, "harmony") == "good",
			"−110 мс → good (ранняя граница Good)")

	await _wait(cond, 5.2)
	_ck(judge.submit_press_at(5.5 + 0.130, "harmony") == "good",
			"+130 мс → good (поздняя граница Good)")

	# 2) Мимо окна Good на 1 мс: empty_press, нота не тронута → Miss по таймеру
	await _wait(cond, 5.7)
	var em_before := empties.size()
	v = judge.submit_press_at(6.0 - 0.111, "harmony")
	_ck(v == "empty_press", "−111 мс → empty_press (вне Good)")
	_ck(empties.size() == em_before + 1 and str(empties[em_before]) == "harmony",
			"empty_press сигнал с kind дорожки")
	_ck(_count(verdicts, n6) == 0, "нота после empty_press не судится")
	await _wait(cond, 6.3)
	_ck(_verdict_of(verdicts, n6) == "miss", "пропуск ноты → Miss по таймеру")

	# 3) Пресс чужого kind (В.1.1): chord-пресс не трогает harmony-ноту
	await _wait(cond, 6.7)
	_ck(judge.submit_press_at(7.0, "harmony") == "perfect", "harmony-пресс в ноту")
	var em2 := empties.size()
	_ck(judge.submit_press_at(7.001, "chord") == "empty_press",
			"chord-пресс рядом с harmony-нотой → empty_press")
	_ck(_count(verdicts, n7) == 1, "чужая дорожка не тронута (≤1 оценки)")
	_ck(empties.size() == em2 + 1, "штраф ушёл на дорожку chord")

	# 4) Анти-дребезг 0.18 с: дабл-пресс глотается целиком
	await _wait(cond, 7.7)
	_ck(judge.submit_press_at(8.0, "chord") == "perfect", "chord-пресс в chord-ноту")
	var em3 := empties.size()
	_ck(judge.submit_press_at(8.5, "chord") == "empty_press", "пустой пресс №1 → штраф")
	_ck(judge.submit_press_at(8.55, "chord") == "",
			"дабл через 50 мс → проглочен (анти-дребезг 0.18 с)")
	_ck(empties.size() == em3 + 1, "штраф ОДИН, а не два")

	# 5) Оффсет сдвигает вердикт: −90 мс + оффсет +100 → perfect.
	#    В дереве эффективный оффсет судья берёт у AudioManager (калибровка
	#    применяется сразу) — выставляем ОБОИХ и возвращаем AM как был.
	var am = root.get_node_or_null("/root/AudioManager")
	var am_off_saved := 0.0
	if am != null:
		am_off_saved = float(am.audio_offset_ms)
		am.set_audio_offset_ms(100.0)
	judge.audio_offset_ms = 100.0
	await _wait(cond, 8.8)
	_ck(judge.submit_press_at(9.0 - 0.090, "harmony") == "perfect",
			"оффсет +100 мс: нажатие −90 мс → perfect")
	judge.audio_offset_ms = 0.0
	if am != null:
		am.set_audio_offset_ms(am_off_saved)

	# 6) Фокус-аут: пауза судьи — Miss невозможен; резюм списывает без штрафа
	await _wait(cond, 10.5)
	judge.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_ck(judge.paused, "фокус-аут: судья на паузе")
	await _wait(cond, 11.4)
	_ck(_count(verdicts, n9) == 0, "фокус-аут: Miss не начислен")
	judge.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_ck(not judge.paused, "резюм фокуса: судья работает")
	await process_frame
	await process_frame
	_ck(_count(verdicts, n9) == 0, "после резюма просроченная нота списана без Miss")

	cond.stop()

	if _fail == 0 and _pass > 0:
		print("RHYTHM JUDGE GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("RHYTHM JUDGE GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
