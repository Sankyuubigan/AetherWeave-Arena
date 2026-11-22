extends SceneTree

## Probe Q16 Шаг 4 (PRP §Шаг 4): RhythmJudge — окна Perfect −65..+90 мс /
## Good −140..+165 мс (границы ±1 мс), оффсет сдвигает вердикт, второй клик
## по тому же note_id игнорируется, пропуск ноты → Miss, фокус-аут без Miss.
## EXIT 0 = PASS.

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
	print("=== PROBE: Q16 Шаг 4 — RhythmJudge ===")
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

	var verdicts := []
	judge.note_judged.connect(func(id, v): verdicts.append([id, v]))

	# Ноты на сетке
	var n1 := judge.register_note("harmony", 3.0)
	var n2 := judge.register_note("harmony", 3.5)
	var n3 := judge.register_note("harmony", 4.0)
	var n4 := judge.register_note("harmony", 4.5)
	var n5 := judge.register_note("harmony", 5.0)
	var n6 := judge.register_note("harmony", 6.0)
	var n7 := judge.register_note("harmony", 7.0)
	_ck(judge._next_id == 7, "регистрация нот: монотонные note_id")

	# 1) Границы окон ±1 мс
	await _wait(cond, 2.8)
	judge.submit_press_at(3.0 - 0.065)
	await process_frame
	_ck(_verdict_of(verdicts, n1) == "perfect", "−65 мс → perfect (ранняя граница)")

	judge.submit_press_at(3.0)
	await process_frame
	_ck(_count(verdicts, n1) == 1, "второй клик по той же ноте игнорируется (≤1 оценки)")

	await _wait(cond, 3.2)
	judge.submit_press_at(3.5 - 0.066)
	await process_frame
	_ck(_verdict_of(verdicts, n2) == "good", "−66 мс → good (вне Perfect, внутри Good)")

	await _wait(cond, 3.7)
	judge.submit_press_at(4.0 + 0.090)
	await process_frame
	_ck(_verdict_of(verdicts, n3) == "perfect", "+90 мс → perfect (поздняя граница)")

	await _wait(cond, 4.2)
	judge.submit_press_at(4.5 + 0.091)
	await process_frame
	_ck(_verdict_of(verdicts, n4) == "good", "+91 мс → good")

	# 2) Мимо окон: нажатие без вердикта; нота добивается Miss по таймеру
	await _wait(cond, 4.7)
	judge.submit_press_at(5.0 - 0.141)
	await process_frame
	_ck(_count(verdicts, n5) == 0, "−141 мс → нажатие мимо всех окон, нота не тронута")
	await _wait(cond, 5.2)
	_ck(_verdict_of(verdicts, n5) == "miss", "пропуск ноты → Miss по таймеру")

	# 3) Оффсет сдвигает вердикт: −90 мс + оффсет +100 → perfect.
	#    В дереве эффективный оффсет судья берёт у AudioManager (калибровка
	#    применяется сразу, Шаг 4) — выставляем ОБОИХ и возвращаем AM как был.
	var am = root.get_node_or_null("/root/AudioManager")
	var am_off_saved := 0.0
	if am != null:
		am_off_saved = float(am.audio_offset_ms)
		am.set_audio_offset_ms(100.0)
	judge.audio_offset_ms = 100.0
	await _wait(cond, 5.7)
	judge.submit_press_at(6.0 - 0.090)
	await process_frame
	_ck(_verdict_of(verdicts, n6) == "perfect", "оффсет +100 мс: нажатие −90 мс → perfect")
	judge.audio_offset_ms = 0.0
	if am != null:
		am.set_audio_offset_ms(am_off_saved)

	# 4) Фокус-аут: пауза судьи — Miss невозможен; резюм списывает без штрафа
	await _wait(cond, 6.5)
	judge.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_ck(judge.paused, "фокус-аут: судья на паузе")
	await _wait(cond, 7.4)
	_ck(_count(verdicts, n7) == 0, "фокус-аут: Miss не начислен")
	judge.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_ck(not judge.paused, "резюм фокуса: судья работает")
	await process_frame
	await process_frame
	_ck(_count(verdicts, n7) == 0, "после резюма просроченная нота списана без Miss")

	cond.stop()

	if _fail == 0 and _pass > 0:
		print("RHYTHM JUDGE GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("RHYTHM JUDGE GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
