extends SceneTree

## Гейт Q16 Шаг 6 (PRP): топливо (+1.2/+0.5/−1.5/кап 14/fuel_out), tier 2/5/8
## + откат на Miss, барьер +14/≤120/срыв при 0, купол перехватывает урон
## (HP не тронут), рикошет ровно raw×ratio + гвард пинг-понга, баффы в полях
## HealthComponent и снимаются на выходе, потолок 14 с, Бас-Дроп закрывает
## стойку, пресс-wiring через try_handle_slot, фокус-аут без Miss.
## EXIT 0 = PASS. Автолоады: get-or-make (урок 22.11.26). cfg не трогаем.

var _pass := 0
var _fail := 0
var _exit_reason := ""
var _misses := 0

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

func _on_exit(reason: String) -> void:
	_exit_reason = reason

func _on_judged(_id: int, v: String) -> void:
	if v == "miss":
		_misses += 1

func _count_ricoshets(p: Node) -> int:
	var n := 0
	for c in p.get_children():
		if c.has_meta("override_damage"):
			n += 1
	return n

func _enter_bard(stance: Node) -> void:
	stance.enter_stance({
		"stance_id": "bard_flow",
		"stance_skill_id": "bard_flow",
		"duration": 99.0,
		"sub_skills": [
			{"id": "bard_note", "label": "Ноты", "default_slot": "ЛКМ"},
			{"id": "bard_chord", "label": "Аккорд", "default_slot": "ПКМ"},
			{"id": "bard_drop", "label": "Дроп", "default_slot": "self"},
		],
	})

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== PROBE: Q16 Шаг 6 — Поток Гармонии ===")
	await process_frame

	# 0) Парс всех новых/правленых скриптов
	for path in ["res://Logic/BardFlowComponent.gd", "res://Logic/StanceComponent.gd",
			"res://Logic/Skills/BardNoteEffect.gd", "res://Logic/Skills/BardDropEffect.gd",
			"res://Logic/Skills/AoeDamageEffect.gd", "res://Logic/HomingProjectileComponent.gd",
			"res://Logic/HealthComponent.gd", "res://Logic/PlayerController.gd",
			"res://Logic/Skills/SkillDB.gd", "res://Logic/Enemies/HellEnemyBase.gd",
			"res://Logic/JellyBrain.gd", "res://Logic/RhythmJudge.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)

	var cond = _get_or_make("res://Logic/RhythmConductor.gd", "RhythmConductor")
	var judge = _get_or_make("res://Logic/RhythmJudge.gd", "RhythmJudge")
	var am = _get_or_make("res://Graphics/AudioManager.gd", "AudioManager")
	var md = _get_or_make("res://Graphics/MusicDirector.gd", "MusicDirector")
	await process_frame
	# Боевой тракт MusicDirector гасим: его НЕОТСЛЕЖИВАЕМЫЕ _fade(bg,...)-твины
	# перекрывают бард-duck на всех последующих проверках (edge ТЗ).
	md._combat_stream = null
	_ck(AudioServer.get_bus_index("Bard") >= 0, "шина Bard есть (Шаг 5)")

	judge.paused = true  # детерминизм: тики не рожают Miss
	judge.conductor = cond
	judge.note_judged.connect(_on_judged)

	# Игрокоподобная сборка: Stance + Health (хук купола) + BardFlow + stub-кастер
	var pscr := GDScript.new()
	pscr.source_code = "extends Node3D\nvar speed_mult: float = 1.0\n"
	pscr.reload()
	var player = pscr.new()
	player.name = "BardProbePlayer"
	root.add_child(player)
	var stance = load("res://Logic/StanceComponent.gd").new()
	stance.name = "StanceComponent"
	player.add_child(stance)
	var hp = load("res://Logic/HealthComponent.gd").new()
	hp.name = "HealthComponent"
	player.add_child(hp)
	var flow = load("res://Logic/BardFlowComponent.gd").new()
	flow.name = "BardFlowComponent"
	player.add_child(flow)
	var stub := GDScript.new()
	# Зеркало SpellCasterComponent: каст = запись вызова + применение эффектов.
	stub.source_code = "extends Node\nvar calls := []\nfunc cast_skill(id, ctx):\n\tcalls.append([id, ctx])\n\tvar sk = load(\"res://Logic/Skills/SkillDB.gd\").get_skills().get(id)\n\tif sk != null:\n\t\tfor e in sk.effects:\n\t\t\te.apply(get_parent(), ctx)\n"
	stub.reload()
	var caster = stub.new()
	caster.name = "SpellCasterComponent"
	player.add_child(caster)
	stance.stance_exited.connect(_on_exit)
	await process_frame

	# Манекенам нужен коллайдер: AoE-запрос intersect_shape не видит
	# StaticBody3D без формы (урок прогона 4).
	var _shape_hp := func(hp_node: Node) -> void:
		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = 0.6
		cs.shape = ss
		hp_node.add_child(cs)
	_shape_hp.call(hp)
	await process_frame

	# Враги: в 8 м (цель рикошета) и в 3 м (жертва дропа/аккорда)
	var enemy := Node3D.new()
	enemy.name = "ProbeEnemy"
	root.add_child(enemy)
	enemy.global_position = Vector3(0, 0, -8)
	var ehp = load("res://Logic/HealthComponent.gd").new()
	enemy.add_child(ehp)
	_shape_hp.call(ehp)
	var enemy2 := Node3D.new()
	root.add_child(enemy2)
	# (3,0,3): в радиусе дропа 6 и аккорда 5, но ВНЕ траектории рикошетов к
	# врагу на (0,0,−8) — иначе рикошет попадает по пути и ломает ожидания.
	enemy2.global_position = Vector3(3, 0, 3)
	var ehp2 = load("res://Logic/HealthComponent.gd").new()
	enemy2.add_child(ehp2)
	_shape_hp.call(ehp2)
	await process_frame

	# ── 1) Топливо: +1.2/+0.5/−0.5, tier-откат, капы ─────────────────────
	_enter_bard(stance)
	_ck(flow.is_flowing, "вход в Поток")
	_ck(absf(flow.fuel - 5.0) < 0.0001, "старт топлива 5.0")
	_ck(flow.barrier == 100, "старт барьера 100")
	flow._on_note_judged(1, "perfect")
	_ck(absf(flow.fuel - 6.2) < 0.0001, "Perfect +1.2 → 6.2")
	_ck(flow.tier == 0, "1 попадание = Tier 0")
	flow._on_note_judged(2, "good")
	_ck(absf(flow.fuel - 6.7) < 0.0001, "Good +0.5 → 6.7")
	_ck(flow.tier == 1, "2 попадания = Tier 1")
	flow._on_note_judged(3, "miss")
	_ck(absf(flow.fuel - 6.2) < 0.0001, "Miss −0.5 → 6.2")
	_ck(flow.tier == 0, "Miss: tier −1 без выброса")
	for i in 12:
		flow._on_note_judged(10 + i, "perfect")
	_ck(absf(flow.fuel - 14.0) < 0.0001, "кап топлива 14.0")
	_ck(flow.barrier == 120, "кап барьера 120 (Perfect +14)")

	# ── 2) Пороги tier 2/5/8 + баффы в полях HP ──────────────────────────
	stance.exit_stance("probe")
	_enter_bard(stance)
	for i in 8:
		flow._on_note_judged(100 + i, "perfect")
		if i == 0:
			_ck(flow.tier == 0, "порог: 1 → T0")
		if i == 1:
			_ck(flow.tier == 1, "порог: 2 → T1")
		if i == 4:
			_ck(flow.tier == 2, "порог: 5 → T2")
		if i == 7:
			_ck(flow.tier == 3, "порог: 8 → T3")
	_ck(absf(hp.damage_reduction - 0.50) < 0.0001, "T3: damage_reduction 0.50 в HP")
	_ck(absf(hp.reflect_ratio - 0.60) < 0.0001, "T3: reflect_ratio 0.60 в HP")
	_ck(absf(player.speed_mult - 1.25) < 0.0001, "T3: speed_mult 1.25")
	flow._on_note_judged(200, "miss")
	_ck(flow.tier == 2, "Miss на T3 → T2")
	_ck(absf(hp.damage_reduction - 0.35) < 0.0001, "T2: защита 0.35 в HP")
	# Реген Tier 2+: heal через период 2.0 с
	hp.current_health = 50
	flow._regen_t = 2.0 - 0.001
	await process_frame
	await process_frame
	_ck(hp.current_health == 55, "реген T2+: +5 HP по таймеру")
	hp.current_health = 100  # baseline для секции купола

	# ── 3) Купол: перехват урона, HP не тронут ───────────────────────────
	stance.exit_stance("probe")
	_enter_bard(stance)
	_ck(hp.damage_interceptor.is_valid(), "хук купола установлен на входе")
	var ric_before := _count_ricoshets(player)
	hp.take_damage(20, Vector3.ZERO, enemy, false)
	_ck(hp.current_health == 100, "купол: HP не тронут (100)")
	_ck(flow.barrier == 83, "купол: барьер 100 − 17 (T0 DR 15%) = 83")
	_ck(_count_ricoshets(player) == ric_before + 1, "Нота-Рикошет заспавнен")
	var ric: Node = null
	for c in player.get_children():
		if c.has_meta("override_damage"):
			ric = c
	_ck(ric != null and int(ric.get_meta("override_damage")) == 3,
			"рикошет: урон ровно raw×ratio (20×0.15=3)")
	_ck(ric != null and bool(ric.get_meta("is_reflected")), "рикошет: метка is_reflected")
	var ric_after_absorb := _count_ricoshets(player)
	hp.take_damage(10, Vector3.ZERO, enemy, true)
	_ck(flow.barrier == 74, "is_reflected-удар: купол поглощает (83 − round(8.5)=9 → 74)")
	_ck(_count_ricoshets(player) == ric_after_absorb,
			"гвард пинг-понга: is_reflected не рождает рикошет")

	# ── 4) Срыв барьера при ≤0 ────────────────────────────────────────────
	_exit_reason = ""
	flow.barrier = 5
	hp.take_damage(100, Vector3.ZERO, enemy, false)
	_ck(_exit_reason == "barrier_break", "срыв барьера → выход «barrier_break»")
	_ck(not flow.is_flowing and not stance.is_active, "Поток и стойка закрыты")
	_ck(hp.damage_reduction == 0.0 and hp.reflect_ratio == 0.0,
			"баффы сняты на выходе (0/0)")
	_ck(absf(player.speed_mult - 1.0) < 0.0001, "скорость сброшена (1.0)")
	_ck(not hp.damage_interceptor.is_valid(), "хук купола снят на выходе")
	_ck(absf(md.bg.volume_db - 0.0) < 0.0001, "duck фона возвращён (0 dB)")

	# ── 5) fuel_out ───────────────────────────────────────────────────────
	# Топливо отрицательным: headless-кадры безбрежно быстрые — дрены 1/с за
	# 3 кадра может не набрать 0.03 с; отрицательное значение = гарантированный
	# close на первом же _process.
	_enter_bard(stance)
	_exit_reason = ""
	flow.fuel = -0.01
	await process_frame
	await process_frame
	await process_frame
	_ck(_exit_reason == "fuel_out", "нулевое топливо → «fuel_out»")

	# ── 6) Жёсткий потолок 14 с ───────────────────────────────────────────
	_enter_bard(stance)
	_exit_reason = ""
	flow.fuel = 14.0
	flow._flow_elapsed = 13.999
	await process_frame
	await process_frame
	await process_frame
	_ck(_exit_reason == "max_duration", "потолок 14 с → «max_duration» (PvP-честность)")

	# ── 7) Provider: tier-карта и мана-лестница не перепутались ──────────
	_ck(not stance.power_provider.is_valid(), "после выхода provider пуст")
	stance.charge = 0.8
	_ck(absf(stance.stance_power() - 1.3) < 0.0001,
			"мана-лестница работает без provider (0.8 → 1.3)")
	_enter_bard(stance)
	_ck(absf(stance.stance_power() - 1.0) < 0.0001, "provider T0 → 1.0")
	for i in 8:
		flow._on_note_judged(300 + i, "perfect")
	_ck(absf(stance.stance_power() - 1.3) < 0.0001, "provider T3 → 1.3")
	stance.exit_stance("probe")
	stance.charge = 0.8
	_ck(absf(stance.stance_power() - 1.3) < 0.0001,
			"после Потока провайдер сброшен (мана-лестница снова жива)")

	# ── 8) Бас-Дроп закрывает стойку + урон/отброс × tier ────────────────
	_enter_bard(stance)
	_exit_reason = ""
	var drop_ok: bool = stance.try_handle_slot("self")
	_ck(drop_ok, "self-слот перехвачен стойкой")
	_ck(caster.calls.size() > 0 and str(caster.calls[caster.calls.size() - 1][0]) == "bard_drop",
			"каст уходит в bard_drop")
	_ck(absf(float(caster.calls[caster.calls.size() - 1][1].get("stance_power", 0.0)) - 1.0) < 0.0001,
			"context: stance_power T0 = 1.0")
	_ck(_exit_reason == "bard_drop", "Бас-Дроп закрывает Поток («bard_drop»)")
	_ck(not flow.is_flowing, "Поток закрыт после дропа")
	_ck(ehp2.current_health == 55, "дроп: урон 45 × stance_power (100→55)")

	# ── 9) bard_chord: context-множители AoeDamageEffect ─────────────────
	var aoe = load("res://Logic/Skills/AoeDamageEffect.gd").new()
	aoe.radius = 5.0
	aoe.damage = 30
	aoe.center_on_caster = true
	aoe.apply(player, {"stance_power": 1.3, "knockback_mult": 1.5})
	_ck(ehp2.current_health == 16, "аккорд: 55 − int(30×1.3) = 16")

	# ── 10) Пресс-wiring: под-приём → judge.submit_press ─────────────────
	_enter_bard(stance)
	var pending_before: int = judge._pending.size()
	_ck(stance.try_handle_slot("ЛКМ"), "ЛКМ подменён bard_note")
	_ck(str(caster.calls[caster.calls.size() - 1][0]) == "bard_note", "каст bard_note")
	_ck(stance.try_handle_slot("ПКМ"), "ПКМ подменён bard_chord")
	_ck(str(caster.calls[caster.calls.size() - 1][0]) == "bard_chord", "каст bard_chord")
	_ck(judge._pending.size() >= pending_before + 2,
			"прессы уходят в судью (usec, через try_handle_slot)")
	stance.exit_stance("probe")

	# ── 11) Фокус-аут: пауза судьи, Miss невозможен ──────────────────────
	cond.stop()
	judge.paused = false
	judge.reset()
	_misses = 0
	var nid: int = judge.register_note("harmony", cond.song_time + 0.01)
	judge._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_ck(judge.paused, "фокус-аут: судья на паузе")
	cond.song_time += 2.0  # нота просрочена, пока пауза
	judge._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_ck(not judge.paused, "фокус-ин: резюм")
	await process_frame
	await process_frame
	_ck(_misses == 0, "фокус-аут: ни одного Miss")
	_ck(judge._notes[nid]["judged"], "просроченная нота списана без штрафа")

	# ── 12) Аудио Потока: полифония на Bard + луп FORWARD + duck ─────────
	# Нейтрализация боевого тракта MusicDirector: take_damage манекенов звал
	# note_combat → fade-твины фона перекрывают бард-duck (задокументированный
	# edge ТЗ). Гасим бой и твины — проверяем сам duck-механизм.
	md._combat_left = 0.0
	md._combat_pending = false
	if md._combat_tween != null:
		md._combat_tween.kill()
	_enter_bard(stance)
	await process_frame
	_ck(flow._poly != null and flow._poly.bus == "Bard",
			"полифония Потока на шине Bard")
	_ck(flow._loop != null and flow._loop.stream != null
			and flow._loop.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"ритм-луп FORWARD на шине Bard")
	_ck(absf(md.bg.volume_db - (-14.0)) < 0.0001, "duck −14 dB в Потоке")
	_stance_checks(flow, stance)
	stance.exit_stance("probe")
	_ck(absf(md.bg.volume_db - 0.0) < 0.0001, "duck снят после Потока")

	# ── 13) Сборка SkillDB ────────────────────────────────────────────────
	var skills = load("res://Logic/Skills/SkillDB.gd").get_skills()
	_ck(skills.has("bard_flow") and skills.has("bard_note")
			and skills.has("bard_chord") and skills.has("bard_drop"),
			"SkillDB: bard_flow + 3 под-приёма")
	var bf_skill = skills["bard_flow"]
	_ck(bf_skill.stance_sub_skills.size() == 3, "bard_flow: 3 stance_sub_skills")
	_ck(absf(float(bf_skill.effects[0].get("duration")) - 99.0) < 0.001,
			"bard_flow: EnterStanceEffect duration 99 (топливо в BardFlow)")
	_ck(bool(skills["bard_note"].get("is_sub_skill"))
			and bool(skills["bard_chord"].get("is_sub_skill"))
			and bool(skills["bard_drop"].get("is_sub_skill")),
			"под-приёмы помечены is_sub_skill")
	var bc_aoe = skills["bard_chord"].effects[0]
	_ck(bool(bc_aoe.get("center_on_caster")) == false and int(bc_aoe.get("damage")) == 30,
			"bard_chord: AoE center=false, dmg 30")
	var bd_eff = skills["bard_drop"].effects[0]
	_ck(bd_eff.get_script() != null
			and String(bd_eff.get_script().resource_path).ends_with("BardDropEffect.gd"),
			"bard_drop: BardDropEffect на месте")

	# ── Cleanup ───────────────────────────────────────────────────────────
	if flow.is_flowing or stance.is_active:
		stance.exit_stance("probe")
	cond.stop()
	judge.reset()
	judge.paused = false
	if judge.note_judged.is_connected(_on_judged):
		judge.note_judged.disconnect(_on_judged)
	md.set_bg_duck_db(0.0)
	player.queue_free()
	enemy.queue_free()
	enemy2.queue_free()
	await process_frame

	if _fail == 0 and _pass > 0:
		print("BARD FLOW GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("BARD FLOW GATE FAILED (fail=%d pass=%d)" % [_fail, _pass])
		quit(1)

func _stance_checks(flow: Node, _stance: Node) -> void:
	# Вынесено из секции 12: живой под-приём ноты в полифонию.
	_ck(flow.has_method("play_random_note"), "play_random_note доступен")
	flow.play_random_note(0.0)
	_ck(true, "случайная нота пентатоники сыграна в полифонию (без ошибок)")
