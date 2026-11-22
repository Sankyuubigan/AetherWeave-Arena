extends Node

## PLL-часы ритма (Q16 Шаг 4, ТЗ спеца): монотонные song_time-часы, подтянутые
## к аудио-времени лупа (формула MusicDirector: playback_pos + time_since_mix
## − output_latency). Расписание долей выдаётся ЗАРАНЕЕ (lookahead 1.5 с) —
## BardFlowComponent планирует ноты по горизонту, VFX ведёт визуал.
## Logic-only: состояние здесь, UI слушает сигналы. Сглаженное время для
## визуала — filtered_time (1€-фильтр).

signal beat_tick(bar: int, beat: int)
signal subdivision_tick(bar: int, eighth: int)

const OneEuro := preload("res://Logic/OneEuroFilter.gd")

## Плейтест 22.11.26: жёсткий снэп УБРАН. audio_time() — позиция БОЕВОГО
## лупа (длина ≠ ритм-сетки loop_len): снэп телепортировал часы на секунды →
## все ноты разом в прошлом → масс-Miss → fuel_out при честных попаданиях.
## Подтяжка только мягкая со скоростным плечом; |err| > PLL_TRACK_MAX =
## чужой луп — часы вообще не трогаем (грид честный, музыка фазой уплывает —
## играбельность важнее фазовой точности).
const PLL_TRACK_MAX := 0.35
## Скоростное плечо подтяжки: ≤0.5 с коррекции на 1 с реального времени.
const PULL_SPEED_CAP := 0.5
## Горизонт расписания: события выдаются заранее на 1.5 с.
const LOOKAHEAD := 1.5
## Мягкая подтяжка: err * min(delta * RATE, 1).
const PULL_RATE := 6.0

var is_running := false
var bpm := 120.0
var beat_len := 0.5
var song_time := 0.0
var filtered_time := 0.0
## Длина ритм-лупа барда (Шаг 5: ~16 с, сетка такта 2.0 с). 0 = сетка без зацикливания.
var loop_len := 16.0
## Тест-шов проб (headless): >= 0 — фиктивное аудио-время вместо MusicDirector.
var debug_audio_time := -1.0

var _filter: OneEuro
var _sched_eighth := 0  # индекс следующей восьмой сетки (от старта лупа)

func _ready() -> void:
	_filter = OneEuro.new()

func start(bpm_: float = 120.0) -> void:
	bpm = maxf(bpm_, 30.0)
	beat_len = 60.0 / bpm
	song_time = 0.0
	filtered_time = 0.0
	_sched_eighth = 0
	is_running = true

func stop() -> void:
	is_running = false

## Аудио-время по формуле MusicDirector. −1 = луп не играет (headless,
## старт-прайм) — PLL честно тикает сам (позиция плеера стоит).
func _audio_time() -> float:
	if debug_audio_time >= 0.0:
		return debug_audio_time
	var md := get_node_or_null("/root/MusicDirector")
	if md != null and md.has_method("audio_time"):
		return md.audio_time()
	return -1.0

## Зацикленная разница (a − b) в [−loop/2, loop/2).
func _loop_diff(a: float, b: float) -> float:
	if loop_len <= 0.0:
		return a - b
	return fmod(a - b + loop_len * 0.5, loop_len) - loop_len * 0.5

func _process(delta: float) -> void:
	if not is_running:
		return
	song_time += delta
	var at := _audio_time()
	if at >= 0.0:
		var err := _loop_diff(at, song_time)
		if absf(err) > PLL_TRACK_MAX:
			pass  # чужой луп: телепорт часов = масс-Miss, не трогаем
		else:
			var pull := err * minf(delta * PULL_RATE, 1.0)
			pull = clampf(pull, -delta * PULL_SPEED_CAP, delta * PULL_SPEED_CAP)
			song_time += pull
	filtered_time = _filter.filter(song_time, maxf(delta, 0.000001))
	_schedule()

## Выдаём события сетки ЗАРАНЕЕ: всё, что наступит в пределах LOOKAHEAD.
## Восьмые — максимальное дробление (шестнадцатых НЕТ по ТЗ).
func _schedule() -> void:
	var eighth := beat_len * 0.5
	var horizon := song_time + LOOKAHEAD
	while _sched_eighth * eighth <= horizon:
		var bar := int(_sched_eighth / 8.0)
		var e_in_bar := _sched_eighth % 8
		if e_in_bar % 2 == 0:
			beat_tick.emit(bar, int(e_in_bar / 2.0))
		subdivision_tick.emit(bar, e_in_bar)
		_sched_eighth += 1
