extends SceneTree

## Гейт Шага 7 (Q16): headless-сборка визуала Потока без рендера. Купол,
## кольцо-аура, орбита нот, UI-дуги создаются кодом и тикают кадрами БЕЗ
## ошибок; uniforms/сигналы/ноты/цвета по tier живут. Запуск:
## ...console.exe --headless -s res://Generators/probe_bard_vfx.gd

var _pass := 0
var _fail := 0

func _ck(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("PASS: " + label)
	else:
		_fail += 1
		print("FAIL: " + label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== BARD VFX PROBE ===")
	# 1) Парс скриптов.
	for p in ["res://Graphics/BardFlowUI.gd", "res://Graphics/AcousticBarrierVFX.gd",
			"res://Logic/RhythmJudge.gd", "res://Graphics/MusicSpectrum.gd"]:
		_ck(load(p) != null, "парс " + p)
	# 2) Автолоады в -s работают (урок 22.11.26); гард get-or-make.
	var judge = root.get_node_or_null("RhythmJudge")
	if judge == null:
		judge = load("res://Logic/RhythmJudge.gd").new()
		judge.name = "RhythmJudge"
		root.add_child(judge)
	var cond = root.get_node_or_null("RhythmConductor")
	if cond == null:
		cond = load("res://Logic/RhythmConductor.gd").new()
		cond.name = "RhythmConductor"
		root.add_child(cond)
	# Music bus (в игре создаёт MusicDirector; гард для -s).
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "Music")
	# 3) MusicSpectrum.get_analyzer() (новый публичный метод Шага 7).
	var ms = root.get_node_or_null("MusicSpectrum")
	if ms == null:
		ms = load("res://Graphics/MusicSpectrum.gd").new()
		ms.name = "MusicSpectrum"
		root.add_child(ms)
	_ck(ms.has_method("get_analyzer"), "MusicSpectrum.get_analyzer есть")
	var an = ms.get_analyzer()
	_ck(an != null, "спектр-анализатор шины Music жив")
	# 4) RhythmJudge.get_notes() (новый метод Шага 7).
	_ck(judge.has_method("get_notes"), "RhythmJudge.get_notes есть")
	judge.reset()
	judge.register_note("harmony", 1.5)
	judge.register_note("chord", 2.5)
	_ck(judge.get_notes().size() == 2, "get_notes: 2 ноты в снимке")
	# 5) Стаб игрока + реальные компоненты (как у игрока в _ready).
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar speed_mult: float = 1.0\n"
	stub.reload()
	var pl := Node3D.new()
	pl.set_script(stub)
	root.add_child(pl)
	var flow = load("res://Logic/BardFlowComponent.gd").new()
	flow.name = "BardFlowComponent"
	pl.add_child(flow)
	var dome = load("res://Graphics/AcousticBarrierVFX.gd").new()
	dome.name = "AcousticBarrierVFX"
	pl.add_child(dome)
	var ui = load("res://Graphics/BardFlowUI.gd").new()
	ui.name = "BardFlowUI"
	pl.add_child(ui)
	_ck(pl.get_node_or_null("AcousticBarrierVFX") != null, "купол-узел у игрока")
	_ck(pl.get_node_or_null("BardFlowUI") != null, "UI-узел у игрока")
	# 6) Вне Потока всё скрыто.
	await process_frame
	_ck(not ui._panel.visible, "UI скрыт вне Потока")
	_ck(not dome.visible, "купол скрыт вне Потока")
	# 7) Симуляция Потока: поля + сигналы (как при stance_entered).
	flow.is_flowing = true
	flow.fuel = 10.0
	flow.barrier = 76
	flow.tier = 2
	flow.fuel_changed.emit(flow.fuel)
	flow.barrier_changed.emit(flow.barrier)
	flow.flow_tier_changed.emit(flow.tier)
	for i in 6:
		await process_frame
	_ck(ui._panel.visible, "UI виден в Потоке")
	_ck(dome.visible, "купол виден в Потоке")
	_ck(ui._lane_l != null and ui._lane_r != null, "две дорожки harmony/chord")
	_ck(ui._lane_l._lane_cx != 0.0 and ui._lane_l._y_hit != 0.0,
			"позиция дорожки выставлена (center ±95, y_hit +10)")
	flow.fuel_delta.emit(1.2)
	_ck(ui._timer_pops.size() == 1, "fuel_delta → дельта-попап у таймера")
	# 8) Uniforms купола: время идёт, 12 полос, урон-рябь.
	var mat: ShaderMaterial = dome._mat
	_ck(mat != null and mat.shader != null, "ShaderMaterial купола")
	var t0: float = float(mat.get_shader_parameter("u_time"))
	for i in 4:
		await process_frame
	var t1: float = float(mat.get_shader_parameter("u_time"))
	_ck(t1 > t0, "u_time купола идёт (%.3f→%.3f)" % [t0, t1])
	var bv = mat.get_shader_parameter("bands")
	_ck(bv != null and (bv as PackedFloat32Array).size() == 12, "bands: 12 полос")
	# 9) Цвет по tier: T3 → золото + орбита нот.
	flow.tier = 3
	flow.flow_tier_changed.emit(3)
	for i in 3:
		await process_frame
	var tc = mat.get_shader_parameter("tier_color")
	var col: Color = tc if tc is Color else Color(tc)
	_ck(col.b < 0.6 and col.r > 0.7, "T3 цвет золото (%s)" % col)
	_ck(dome._notes.emitting, "орбита нот-частиц на T3")
	# 9b) Фикс Б (10-ответ): купол едет с телом — центр player.y+0.95 КАЖДЫЙ
	# кадр; кольцо = СЕЧЕНИЕ сферы полом на полу y+0.03 (плейтест-4);
	# DEPTH-кромка только у пола (u_floor_y = player.y + 0.20).
	var dmy: float = dome._mesh.global_position.y
	_ck(absf(dmy - (pl.global_position.y + 0.95)) < 0.001,
			"Фикс Б: центр купола player.y + 0.95 (%.3f)" % dmy)
	var ring_fit := sqrt(1.9 * 1.9 - 0.95 * 0.95)
	var torus := dome._ring.mesh as TorusMesh
	_ck(torus != null and absf(torus.inner_radius - (ring_fit - 0.18)) < 0.0001
			and absf(torus.outer_radius - ring_fit) < 0.0001,
			"кольцо = сечение купола полом %.2f/%.2f (ширина 0.18)" % [ring_fit - 0.18, ring_fit])
	_ck(absf(float(dome._ring.position.y) - 0.03) < 0.0001,
			"Фикс Б: кольцо на полу y+0.03")
	_ck(absf(float(mat.get_shader_parameter("u_floor_y"))
			- (pl.global_position.y + 0.20)) < 0.001,
			"Фикс Б: u_floor_y = player.y + 0.20 (кромка только у пола)")
	_ck(dome._hips_pos(pl) == Vector3.INF,
			"Hips-фолбэк: без скелета → INF (центр по origin игрока)")
	# 10) Рябь от попадания (notify_impact — путь Шага 6).
	dome.notify_impact(pl.global_position + Vector3(0, 1.9, 0))
	var it := float(mat.get_shader_parameter("impact_time"))
	_ck(it > -50.0, "рябь: impact_time записан (%.2f)" % it)
	# 11) Выход из Потока: купол глохнет сразу, баннер причины живёт 2.0 с
	# ПОСЛЕ закрытия стойки (В.4.2). Прямое is_flowing=false (без exit_stance)
	# → last_exit_reason пуст → дефолт «ПОТОК ОТМЕНЁН».
	flow.is_flowing = false
	flow.fuel = 0.0
	for i in 4:
		await process_frame
	_ck(not dome.visible, "купол скрыт после выхода")
	_ck(not dome._notes.emitting, "орбита нот выключена после выхода")
	_ck(ui._panel.visible, "UI жив ПОСЛЕ выхода (баннер причины)")
	_ck(ui._banner_left > 0.0 and str(ui._banner_text) == "ПОТОК ОТМЕНЁН",
			"дефолт-баннер «ПОТОК ОТМЕНЁН»")
	ui._banner_left = 0.001  # ускорить жизнь баннера
	await process_frame
	await process_frame
	_ck(not ui._panel.visible, "баннер погас → UI скрыт")
	# 12) Ре-вход (стойка может открываться повторно).
	flow.is_flowing = true
	flow.fuel = 8.0
	flow.barrier = 100
	flow.tier = 0
	for i in 4:
		await process_frame
	_ck(ui._panel.visible and dome.visible, "ре-вход Потока жив")
	# Cleanup.
	pl.queue_free()
	judge.reset()
	await process_frame
	print("PASS_COUNT=%d FAIL_COUNT=%d" % [_pass, _fail])
	if _fail == 0:
		print("BARD VFX GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("BARD VFX GATE FAILED")
		quit(1)
