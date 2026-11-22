extends Node

## Судья ритма (Q16 Шаг 4; анти-спам — вердикт спеца 09-ответ В.1). Нажатия
## приходят с usec-таймстампом (StanceComponent.try_handle_slot → submit_press)
## и судятся СРАЗО, синхронно: вердикт нужен гейту каста под-приёма.
## Окна (В.1.4): Perfect −55..+70 мс, Good −110..+130 мс (ширина 240 < зазора
## нот 500 мс — окна не перекрываются); нота без оценки к концу окна Good
## = Miss. Пресс СТРОГО своего вида (В.1.1): press(kind) судит только ноты
## этого kind, чужая нота не трогается. Пресс без ноты своего вида в окне
## Good = empty_press (В.1.2): штраф на стороне BardFlowComponent, анти-
## дребезг 0.18 с. ≤1 оценки на note_id. Фокус-аут — пауза судьи: Miss
## невозможен, резюм списывает просроченные ноты без штрафа.

signal note_judged(note_id: int, verdict: String, kind: String)
## Пустой пресс (нет ноты этого kind в окне Good): −1.2 топлива и −1 tier
## считает BardFlowComponent, UI рисует «МИМО» на дорожке kind.
signal empty_press(kind: String)
## Каждое нажатие дорожки — для «прожима» рамки-мишени в UI (Фикс А.3).
signal press_received(kind: String)

const PERFECT_EARLY_MS := -55.0
const PERFECT_LATE_MS := 70.0
const GOOD_EARLY_MS := -110.0
const GOOD_LATE_MS := 130.0
## Анти-дребезг empty_press (В.1.2): минимальный интервал между штрафами в
## часах conductor — случайный даблклик не сжигает двойной штраф за 30 мс,
## а спам мышкой гарантированно сжигает Поток (~2 с).
const EMPTY_DEBOUNCE_S := 0.18
## Гард границ от float-дрейфа (press = note + 0.070 в binary64 даёт
## 0.07000000000000028 — граница должна оставаться внутри окна).
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

var _notes := {}            # note_id → {time, kind, judged}
var _next_id := 0
var _last_empty_t := -100.0  # часы conductor последнего штрафа empty_press

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
	_next_id = 0
	_last_empty_t = -100.0

## Производственный путь: нажатие дорожки kind (В.1.1). Время берётся из
## Time.get_ticks_usec() ЗДЕСЬ (суб-кадровая точность против часов conductor).
## Возвращает вердикт: "perfect" / "good" / "empty_press" или "" (анти-дребезг
## проглотил дабл; пауза судьи). Гейт каста под-приёма — StanceComponent.
func submit_press(kind: String = "") -> String:
	var press := _press_time_from_usec(Time.get_ticks_usec())
	return _judge_press(press, kind)

## Тест-шов проб: нажатие в заданной точке часов (детерминированные границы).
func submit_press_at(press_song_time: float, kind: String = "") -> String:
	return _judge_press(press_song_time, kind)

func _press_time_from_usec(path: int) -> float:
	var now := Time.get_ticks_usec()
	var base: float = conductor.song_time if conductor != null else 0.0
	return base - float(now - path) / 1000000.0

func _time() -> float:
	return conductor.song_time if conductor != null else 0.0

## Синхронное судейство одного пресса (verdikt → гейту каста и сигналам).
func _judge_press(press: float, kind: String) -> String:
	if paused:
		return ""
	press_received.emit(kind)
	var eff := press + _eff_offset_ms() / 1000.0
	var best_id := -1
	var best_diff := 1e9
	for id in _notes:
		var n: Dictionary = _notes[id]
		if n["judged"]:
			continue
		if kind != "" and str(n["kind"]) != kind:
			continue  # В.1.1: чужая дорожка не трогается
		var diff: float = eff - n["time"]
		if absf(diff) < absf(best_diff):
			best_diff = diff
			best_id = id
	if best_id >= 0 and best_diff >= GOOD_EARLY_MS / 1000.0 - EPS \
			and best_diff <= GOOD_LATE_MS / 1000.0 + EPS:
		var verdict := "good"
		if best_diff >= PERFECT_EARLY_MS / 1000.0 - EPS \
				and best_diff <= PERFECT_LATE_MS / 1000.0 + EPS:
			verdict = "perfect"
		_notes[best_id]["judged"] = true  # ≤1 оценки на note_id
		note_judged.emit(best_id, verdict, str(_notes[best_id]["kind"]))
		return verdict
	# В.1.2: пустой пресс — ноты этого kind в окне Good нет. Штраф (топливо/
	# tier у BardFlowComponent) с анти-дребезгом: дабл в пределах 0.18 с
	# глотается целиком. kind == "" (legacy-вызовы без дорожки) — без штрафа.
	if kind == "":
		return ""
	if eff - _last_empty_t < EMPTY_DEBOUNCE_S:
		return ""
	_last_empty_t = eff
	empty_press.emit(kind)
	return "empty_press"

func _process(_delta: float) -> void:
	if paused:
		return
	# Пропуск: нота вышла за конец окна Good без оценки → Miss.
	# Гард ренантности: note_judged мог СИНХРОННО закрыть Поток (fuel_out при
	# массовых промахах) → exit → judge.reset() снёс ноты, а keys()-снапшот
	# держит мёртвые id (SCRIPT ERROR «key '10'» из сессии 22.11.26).
	var now := _time()
	for id in _notes.keys():
		if not _notes.has(id):
			continue
		var n: Dictionary = _notes[id]
		if not n["judged"] and now > n["time"] + GOOD_LATE_MS / 1000.0:
			n["judged"] = true
			note_judged.emit(id, "miss", str(n["kind"]))

func _notification(what: int) -> void:
	## Фокус-аут (ТЗ спеца): судья на паузу, Miss невозможен; резюм списывает
	## просроченные ноты без штрафа (снэп часов по PLL произойдёт сам).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_resume_clean()

func _resume_clean() -> void:
	paused = false
	var now := _time()
	for id in _notes.keys():
		if not _notes.has(id):
			continue  # тот же гард ренантности, что в _process
		var n: Dictionary = _notes[id]
		if not n["judged"] and now > n["time"] + GOOD_LATE_MS / 1000.0:
			n["judged"] = true
