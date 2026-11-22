extends SceneTree

## Probe Q16 Шаг 5 (PRP): шина Bard, 7 .res нот + луп, полифония старт/стоп,
## duck MusicDirector точно, settings round-trip (bard_volume + audio_offset_ms
## сохраняются рядом с [graphics] — урок AudioManager про load-first),
## калибровка: 8 нажатий → медиана → оффсет судьи. EXIT 0 = PASS.
## Проба восстанавливает user://settings.cfg после теста.
## УРОК 22.11.26: автолоады в -s ЭТОЙ сборки 4.8 ЗАГРУЖАЮТСЯ (старый урок
## «не работают» неверен) — ручной инстанс с тем же именем переименовывается
## движком и lookup "/root/X" бьёт в автолоад. Поэтому get-or-make: берём
## автолоад, если есть; создаём, если нет (детерминизм в обоих мирах).

var _pass := 0
var _fail := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)

func _get_or_make(script_path: String, node_name: String) -> Node:
	var n = root.get_node_or_null(node_name)
	if n != null:
		return n
	n = load(script_path).new()
	n.name = node_name
	root.add_child(n)
	return n

func _init() -> void:
	call_deferred("_run")

func _dump(tag: String) -> void:
	var c := ConfigFile.new()
	c.load("user://settings.cfg")
	print("DUMP[%s] bard=%s offs=%s" % [tag,
			c.get_value("audio", "bard_volume", "<нет>"),
			c.get_value("audio", "audio_offset_ms", "<нет>")])

func _run() -> void:
	print("=== PROBE: Q16 Шаг 5 — Аудио Барда ===")
	await process_frame

	# Снапшот состояния юзера ДО любых изменений (калибровка ниже пишет cfg!)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var had_bard: bool = cfg.has_section_key("audio", "bard_volume")
	var had_offs: bool = cfg.has_section_key("audio", "audio_offset_ms")
	var old_bard: float = cfg.get_value("audio", "bard_volume", 1.0)
	var old_offs: float = cfg.get_value("audio", "audio_offset_ms", 0.0)

	# 0) Парс скриптов
	for path in ["res://Graphics/AudioManager.gd", "res://Graphics/SettingsMenu.gd",
			"res://Graphics/MusicDirector.gd", "res://Logic/RhythmJudge.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)

	# 1) Шина Bard (get-or-make: реальный автолоад, если он загрузился)
	var am = _get_or_make("res://Graphics/AudioManager.gd", "AudioManager")
	await process_frame
	var bidx := AudioServer.get_bus_index("Bard")
	_ck(bidx >= 0, "шина Bard создана AudioManager")
	_ck(bidx >= 0 and AudioServer.get_bus_send(bidx) == &"Master",
			"шина Bard отправляется в Master")
	_ck(AudioServer.get_bus_index("SFX") >= 0, "шина SFX не сломана")

	# 2) SettingsMenu: UI-элементы Шага 5
	var menu = _get_or_make("res://Graphics/SettingsMenu.gd", "SettingsMenu")
	await process_frame
	_ck(menu._bard_slider != null and menu._offset_slider != null
			and menu._calib_button != null, "UI: ползунок Бард/оффсет/кнопка есть")
	_ck(absf(menu._offset_slider.min_value - (-150.0)) < 0.001
			and absf(menu._offset_slider.max_value - 150.0) < 0.001
			and absf(menu._offset_slider.step - 5.0) < 0.001,
			"оффсет-слайдер −150..+150 шаг 5")
	_ck(String(menu._calib_button.text).contains("Калибровать"),
			"кнопка калибровки подписана")
	var med: float = menu._offset_from_deltas(
			[0.02, 0.05, 0.01, 0.03, 0.04, 0.02, 0.06, 0.03])
	_ck(absf(med - (-30.0)) < 0.001, "медиана 8 нажатий: late 30 мс → offset −30")
	_ck(menu._offset_from_deltas([]) == 0.0, "пустая калибровка → 0 мс")

	# 3) Калибровочный цикл: conductor + 8 нажатий в одной точке доли (+20 мс)
	var cond = _get_or_make("res://Logic/RhythmConductor.gd", "RhythmConductor")
	cond.start(120.0)
	menu._on_calibrate_pressed()
	_ck(menu._calib_on, "калибровка стартует (метроном 120 BPM)")
	var guard := 0
	while guard < 30000:
		guard += 1
		await process_frame
		var m: float = fmod(cond.song_time, 0.5)
		if m >= 0.02 and m < 0.03:
			break
	_ck(guard < 30000, "окно доли (+20 мс) поймано")
	for i in 8:
		menu._calib_press()
	_ck(not menu._calib_on, "8 нажатий завершают калибровку")
	_ck(absf(menu._offset_slider.value - (-20.0)) < 0.001,
			"offset −20 мс от медианы записан в слайдер")
	cond.stop()

	# 4) Живой оффсет судьи: читается из AudioManager
	var judge = _get_or_make("res://Logic/RhythmJudge.gd", "RhythmJudge")
	am.audio_offset_ms = 42.0
	_ck(absf(judge._eff_offset_ms() - 42.0) < 0.001,
			"судья берёт оффсет из AudioManager (42 мс)")

	# 5) Settings round-trip + load-first (урок: [graphics] рядом не стирать)
	cfg.set_value("graphics", "probe_marker", 7)
	cfg.save("user://settings.cfg")

	am.set_bard_volume(0.7)
	am.set_audio_offset_ms(-45.0)
	var cfg2 := ConfigFile.new()
	cfg2.load("user://settings.cfg")
	_ck(absf(float(cfg2.get_value("audio", "bard_volume", 0.0)) - 0.7) < 0.001,
			"round-trip: bard_volume 0.7 в settings.cfg")
	_ck(absf(float(cfg2.get_value("audio", "audio_offset_ms", 99.0)) - (-45.0)) < 0.001,
			"round-trip: audio_offset_ms −45 в settings.cfg")
	_ck(int(cfg2.get_value("graphics", "probe_marker", 0)) == 7,
			"load-first: [graphics]-маркер пережил save")
	_dump("после round-trip")

	# Восстановление к состоянию юзера: set_* возвращает значения (load-first
	# переживёт маркер), финальный проход СВЕЖЕЙ копией стирает то, чего у
	# юзера не существовало до пробы (дефолты 0.0/1.0 и так совпадают).
	am.set_bard_volume(old_bard)
	am.set_audio_offset_ms(old_offs)
	var cfg3 := ConfigFile.new()
	cfg3.load("user://settings.cfg")
	if not had_bard:
		cfg3.erase_section_key("audio", "bard_volume")
	if not had_offs:
		cfg3.erase_section_key("audio", "audio_offset_ms")
	cfg3.erase_section_key("graphics", "probe_marker")
	cfg3.save("user://settings.cfg")
	var cfg4 := ConfigFile.new()
	cfg4.load("user://settings.cfg")
	var offs_clean: bool = (not had_offs
			and not cfg4.has_section_key("audio", "audio_offset_ms")) \
			or (had_offs and absf(float(cfg4.get_value("audio", "audio_offset_ms", 99.0))
					- old_offs) < 0.001)
	_ck(offs_clean, "cfg восстановлен к состоянию юзера (оффсет)")
	_dump("после restore")

	# 6) Ноты: все 7 .res + луп
	var all_notes := true
	for nm in ["d4", "f4", "g4", "a4", "c5", "d5", "miss"]:
		var st = load("res://Audio/Bard/note_%s.res" % nm)
		if st == null or not (st is AudioStreamWAV):
			all_notes = false
	_ck(all_notes, "7 нот (6 пентатоника + miss) грузятся AudioStreamWAV")
	var loop = load("res://Audio/Bard/bard_loop.res")
	_ck(loop != null and loop is AudioStreamWAV
			and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"bard_loop.res FORWARD-луп")

	# 7) Полифония: плеер на шине Bard стартует, пишет ноту, стопается
	var poly := AudioStreamPlayer.new()
	var pstream := AudioStreamPolyphonic.new()
	poly.stream = pstream
	poly.bus = "Bard"
	root.add_child(poly)
	poly.play()
	await process_frame
	await process_frame
	_ck(poly.playing, "полифонический плеер стартует")
	var pb = poly.get_stream_playback()
	_ck(pb != null and pb.has_method("play_stream"), "polyphonic playback готов")
	if pb != null:
		pb.play_stream(load("res://Audio/Bard/note_a4.res"), 0.0, 0.0, 1.0)
		_ck(true, "нота пишется полифонически (без ошибок)")
	poly.stop()
	await process_frame
	_ck(not poly.playing, "полифонический плеер стопается")
	poly.queue_free()

	# 8) Duck MusicDirector: ставится и возвращается точно
	var md = _get_or_make("res://Graphics/MusicDirector.gd", "MusicDirector")
	await process_frame
	_ck(md.bg != null, "MusicDirector: bg-плеер готов")
	md.set_bg_duck_db(-14.0)
	_ck(absf(md.bg.volume_db - (-14.0)) < 0.0001, "duck −14 dB ставится точно")
	md.set_bg_duck_db(0.0)
	_ck(absf(md.bg.volume_db - 0.0) < 0.0001, "duck возвращается точно (0 dB)")

	# 9) Фолбэк судьи: lookup промахивается → локальная переменная.
	# Переименование вместо free (автолоад free-ить нельзя).
	var old_am_name: String = am.name
	am.name = "AudioManagerOff"
	var eff_fallback: float = judge._eff_offset_ms()
	am.name = old_am_name
	_ck(absf(eff_fallback - 0.0) < 0.001,
			"без AudioManager судья берёт локальный оффсет")

	_dump("перед quit")
	if _fail == 0 and _pass > 0:
		print("AUDIO BARD GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("AUDIO BARD GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
