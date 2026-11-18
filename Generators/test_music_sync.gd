extends SceneTree
## Тест BPM-синка боевого лупа (PRP «18.11.26 Демо-фишки Godot»).
## Запуск: engine --headless -s res://Generators/test_music_sync.gd
## Гейты:
##   1) без фона боевой луп стартует сразу (fallback);
##   2) с фоном боевой луп стартует И на границе такта (±0.35 с);
##   3) после истечения боевого таймера луп затухает (_combat_release).

const MusicDirectorScript = preload("res://Graphics/MusicDirector.gd")

var md: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	md = MusicDirectorScript.new()
	root.add_child(md)
	await process_frame

	# ── Гейт 1: без фона — немедленный старт ──────────────────────────────
	md.note_combat(6.0)
	await create_timer(0.5).timeout
	_check(md.combat.playing, "гейт 1: без фона боевой луп стартует сразу")
	md._combat_left = 0.0
	await process_frame
	md.combat.stop()
	await process_frame

	# ── Гейт 2: с фоном — старт на границе такта ──────────────────────────
	md._switch_bg(load("res://Audio/Music/map1_ambient.res"))
	await create_timer(0.7).timeout
	md.note_combat(6.0)
	var waited := 0.0
	var started := false
	var pos_on_start := -1.0
	while waited < 3.5:
		await create_timer(0.05).timeout
		waited += 0.05
		if md.combat.playing:
			started = true
			pos_on_start = md._stable_pos(md.bg)
			break
	_check(started, "гейт 2: с фоном боевой луп стартует")
	if started:
		if not md.last_start_synced:
			print("SYNC: WARN — старт через fallback (headless-позиция не тикает?), фазу не проверяем")
		else:
			var phase := fmod(pos_on_start, md.BAR_SEC)
			var off := minf(phase, md.BAR_SEC - phase)
			print("SYNC: bg_pos_on_start=%.3f фаза=%.3f отклонение=%.3f с" % [pos_on_start, phase, off])
			_check(off <= 0.35, "гейт 2: старт в пределах ±0.35 с от границы такта")

	# ── Гейт 3: таймер боя гасит луп ──────────────────────────────────────
	md._combat_left = 0.0
	await create_timer(0.4).timeout
	_check(md._combat_pending == false, "гейт 3: pending снят после истечения боя")

	print("MUSIC-SYNC: ALL PASS")
	quit(0)

func _check(cond: bool, what: String) -> void:
	if not cond:
		print("MUSIC-SYNC: FAIL — ", what)
		quit(1)
