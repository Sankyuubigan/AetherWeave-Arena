extends SceneTree

## Probe Q16 Шаг 4 (PRP §Шаг 4): RhythmConductor PLL-ядро.
## Гейт: автолоады в project.godot; headless-сталл — song_time растёт;
## тики beat/eighth сходятся с BPM-сеткой (±1 мс); err > 0.08 → снэп за 1
## кадр; малый err → экспоненциальная подтяжка; 1€-фильтр отдаёт время.
## EXIT 0 = PASS.

const COND := preload("res://Logic/RhythmConductor.gd")

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

func _run() -> void:
	print("=== PROBE: Q16 Шаг 4 — RhythmConductor ===")
	await process_frame

	# 0) Парс + регистрация автолоадов
	for path in ["res://Logic/RhythmConductor.gd", "res://Logic/RhythmJudge.gd",
			"res://Logic/OneEuroFilter.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)
	var pf := FileAccess.open("res://project.godot", FileAccess.READ)
	var txt := pf.get_as_text() if pf else ""
	_ck(txt.contains("RhythmConductor=\"*res://Logic/RhythmConductor.gd\""),
			"автолоад RhythmConductor в project.godot")
	_ck(txt.contains("RhythmJudge=\"*res://Logic/RhythmJudge.gd\""),
			"автолоад RhythmJudge в project.godot")

	# 1) Стаб часов (автолоады в -s не работают — инстанс вручную)
	var cond = COND.new()
	root.add_child(cond)
	await process_frame

	var beats := []
	var eighths := []
	cond.beat_tick.connect(func(b, bt): beats.append([b, bt]))
	cond.subdivision_tick.connect(func(b, e): eighths.append([b, e]))

	cond.start(120.0)
	_ck(cond.is_running and cond.beat_len == 0.5, "старт 120 BPM: бит 0.5 с")
	await create_timer(1.0).timeout
	_ck(cond.song_time > 0.3, "headless-сталл: song_time растёт (%.2f с)" % cond.song_time)
	await create_timer(1.5).timeout

	# 2) Биты на сетке: t = bar*2.0 + beat*0.5, шаг 0.5 ±0.001
	_ck(beats.size() >= 4, "биты выдаются заранее (%d шт.)" % beats.size())
	var grid_ok := true
	for i in beats.size():
		var t: float = beats[i][0] * 2.0 + beats[i][1] * 0.5
		if absf(t - i * 0.5) > 0.001:
			grid_ok = false
	_ck(grid_ok, "биты на сетке 0.5 с (±1 мс), порядок выдачи монотонный")

	# 3) Восьмые: шаг 0.25 ±0.001
	_ck(eighths.size() >= 8, "восьмые выдаются (%d шт.)" % eighths.size())
	var e_ok := true
	for i in eighths.size():
		var t2: float = eighths[i][0] * 2.0 + eighths[i][1] * 0.25
		if absf(t2 - i * 0.25) > 0.001:
			e_ok = false
	_ck(e_ok, "восьмые на сетке 0.25 с (±1 мс)")

	# 4) Подтяжка err 0.2 (≤ PLL_TRACK_MAX): БЕЗ телепорта часов (плейтест
	# 22.11.26: жёсткий снэп телепортировал song_time → масс-Miss). Кап
	# скорости 0.5 с/с: err 0.2 закрывается за ~0.4 с СТЕНОЧНОГО времени —
	# headless-кадры с микроскопическим delta кадровым гардом не ловятся.
	cond.debug_audio_time = cond.song_time + 0.2
	var max_step := 0.0
	var wall0 := Time.get_ticks_usec()
	while absf(cond.song_time - cond.debug_audio_time) > 0.01 and Time.get_ticks_usec() - wall0 < 2000000:
		var prev_st: float = cond.song_time
		await process_frame
		max_step = maxf(max_step, cond.song_time - prev_st)
	_ck(max_step < 0.06, "нет телепорта: шаг часов за кадр ≤ %.3f с" % max_step)
	_ck(absf(cond.song_time - cond.debug_audio_time) <= 0.01,
			"err 0.2 → сходится ограниченной подтяжкой (остаток %.3f с)" % absf(cond.song_time - cond.debug_audio_time))
	cond.debug_audio_time = -1.0
	await process_frame

	# 5) Мягкая подтяжка: аудио-цель ДВИЖЕТСЯ с темпом кадров (как реальный
	# playback), err 0.05 → экспоненциальное затухание за 0.6 с сим-времени
	var start_t: float = cond.song_time
	var audio_sim: float = cond.song_time + 0.05
	var u0 := Time.get_ticks_usec()
	var err0 := 0.05
	while cond.song_time < start_t + 0.6:
		cond.debug_audio_time = audio_sim
		await process_frame
		audio_sim += float(Time.get_ticks_usec() - u0) / 1000000.0
		u0 = Time.get_ticks_usec()
	var err1: float = cond.debug_audio_time - cond.song_time
	_ck(absf(err1) < err0 * 0.25, "малый err → экспоненциальная подтяжка (0.05 → %.4f)" % err1)
	cond.debug_audio_time = -1.0

	# 6) 1€-фильтр отдаёт сглаженное время рядом с точным
	_ck(cond.filtered_time >= 0.0 and absf(cond.filtered_time - cond.song_time) < 0.5,
			"1€-фильтр отдаёт сглаженное время")

	cond.stop()
	_ck(not cond.is_running, "stop останавливает часы")

	if _fail == 0 and _pass > 0:
		print("RHYTHM CONDUCTOR GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("RHYTHM CONDUCTOR GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
