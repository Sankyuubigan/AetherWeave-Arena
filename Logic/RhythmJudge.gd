extends Node

## Судья ритма (Q16 Шаг 4, ТЗ спеца): нажатия приходят с usec-таймстампом
## (ActionBar/под-приём → submit_press), судятся в _process по часам
## RhythmConductor. Окна: Perfect −65..+90 мс, Good −140..+165 мс; дальше —
## нажатие мимо нот без вердикта, а нота без оценки к концу окна Good = Miss.
## ≤1 оценки на note_id (спам-клики игнорируются). Фокус-аут — пауза судьи:
## Miss невозможен, резюм списывает просроченные ноты без штрафа.

signal note_judged(note_id: int, verdict: String)

const PERFECT_EARLY_MS := -65.0
const PERFECT_LATE_MS := 90.0
const GOOD_EARLY_MS := -140.0
const GOOD_LATE_MS := 165.0
## Гард границ от float-дрейфа (press = note + 0.090 в binary64 даёт
## 0.09000000000000035 — граница должна оставаться внутри окна).
const EPS := 0.000001

var conductor: Node = null
## Компенсация задержки звука (Шаг 5, калибровка в SettingsMenu): сдвигает
## оценку нажатия. +мс = игрок слышит звук позже → нажатие «двигается вперёд».
## Пробы/тесты ставят напрямую; в игре живёт в AudioManager (settings.cfg) и
## читается оттуда через _eff_offset_ms() при каждой оценке.
var audio_offset_ms := 0.0
var paused := false

## Калиброванный оффсет: в дереве есть AudioManager (автолоад) → его значение
## (калибровка применяется сразу, без перезапуска); нет (пробы -s) → локальное.
func _eff_offset_ms() -> float:
	var am = get_node_or_null("/root/AudioManager")
	if am != null:
		return float(am.get("audio_offset_ms"))
	return audio_offset_ms

var _notes := {}      # note_id → {time, kind, judged}
var _pending := []    # [{press}] — press в часах conductor
var _next_id := 0

func register_note(kind: String, grid_time: float) -> int:
	## Регистрация ноты по сетке (BardFlowComponent по lookahead conductor).
	var id := _next_id
	_next_id += 1
	_notes[id] = {"time": grid_time, "kind": kind, "judged": false}
	return id

func get_notes() -> Array:
	## Снимок нот для визуала (BardFlowUI, Шаг 7): [{time, kind, judged}].
	var out: Array = []
	for id in _notes:
		out.append(_notes[id])
	return out

func reset() -> void:
	_notes.clear()
	_pending.clear()
	_next_id = 0

func submit_press() -> void:
	## Производственный путь: вызывается при нажатии; время берётся из
	## Time.get_ticks_usec() ЗДЕСЬ (суб-кадровая точность против часов conductor).
	var press := _press_time_from_usec(Time.get_ticks_usec())
	_pending.append({"press": press})

## Тест-шов проб: нажатие в заданной точке часов (детерминированные границы).
func submit_press_at(press_song_time: float) -> void:
	_pending.append({"press": press_song_time})

func _press_time_from_usec(path: int) -> float:
	var now := Time.get_ticks_usec()
	var base: float = conductor.song_time if conductor != null else 0.0
	return base - float(now - path) / 1000000.0

func _time() -> float:
	return conductor.song_time if conductor != null else 0.0

func _process(_delta: float) -> void:
	if paused:
		return
	var now := _time()
	# 1) Судим накопленные нажатия: ближайшая неоценённая нота в окнах Good.
	while not _pending.is_empty():
		var press: float = _pending.pop_front()["press"]
		var eff := press + _eff_offset_ms() / 1000.0
		var best_id := -1
		var best_diff := 1e9
		for id in _notes:
			var n: Dictionary = _notes[id]
			if n["judged"]:
				continue
			var diff: float = eff - n["time"]
			if absf(diff) < absf(best_diff):
				best_diff = diff
				best_id = id
		if best_id < 0 or best_diff < GOOD_EARLY_MS / 1000.0 - EPS \
				or best_diff > GOOD_LATE_MS / 1000.0 + EPS:
			continue  # нажатие вне всех окон — без вердикта (нота не тронута)
		var verdict := "good"
		if best_diff >= PERFECT_EARLY_MS / 1000.0 - EPS \
				and best_diff <= PERFECT_LATE_MS / 1000.0 + EPS:
			verdict = "perfect"
		_notes[best_id]["judged"] = true  # ≤1 оценки на note_id
		note_judged.emit(best_id, verdict)
	# 2) Пропуск: нота вышла за конец окна Good без оценки → Miss.
	for id in _notes.keys():
		var n: Dictionary = _notes[id]
		if not n["judged"] and now > n["time"] + GOOD_LATE_MS / 1000.0:
			n["judged"] = true
			note_judged.emit(id, "miss")

func _notification(what: int) -> void:
	## Фокус-аут (ТЗ спеца): судья на паузу, Miss невозможен; резюм списывает
	## просроченные ноты без штрафа (снэп часов по PLL произойдёт сам).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_resume_clean()

func _resume_clean() -> void:
	paused = false
	_pending.clear()
	var now := _time()
	for id in _notes.keys():
		var n: Dictionary = _notes[id]
		if not n["judged"] and now > n["time"] + GOOD_LATE_MS / 1000.0:
			n["judged"] = true
