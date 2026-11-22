extends SceneTree

## Гейт «Пульса Битвы» (bard_groove, ТЗ спеца 11-ответ): 6 обязательных гейтов
## ТЗ + покрытие выходов/буфов/купола/Крещендо-пути. Детерминизм: cond.stop() +
## ручной song_time (sync-блок атомарен — часы заморожены, квирк headless);
## временные выходы — прямые вызовы _process(delta) с подменой полей
## (fuel-паттерн Потока: стеночные кадры ненадёжны, delta суб-мс).

var _fails := 0
var _count := 0
var G := load("res://Logic/BardGrooveComponent.gd")  # консты для ожиданий

func _init() -> void:
	# ── Стаб игрока: CharacterBody3D — реальные условия (урок dome_real_scene) ──
	var player := CharacterBody3D.new()
	player.name = "GrooveProbePlayer"
	root.add_child(player)
	player.global_position = Vector3(0, 1, 0)

	# Стаб HP: component _apply_buffs пишет damage_reduction/reflect_ratio.
	var hp_src := GDScript.new()
	hp_src.source_code = "extends Node\nvar damage_reduction := 0.0\nvar reflect_ratio := 0.0\n"
	hp_src.reload()
	var hp_stub: Node = hp_src.new()
	hp_stub.name = "HealthComponent"
	player.add_child(hp_stub)

	var groove: Node = G.new()
	groove.name = "BardGrooveComponent"
	player.add_child(groove)

	# UI-оверлей (парс гейтится отдельно; здесь — _ready не падает headless).
	var ui: Node = load("res://Graphics/BardGrooveUI.gd").new()
	ui.name = "BardGrooveUI"
	player.add_child(ui)

	# Реальный SpellCaster + камера: полный cast_skill("fireball") через
	# НАСТОЯЩИЙ путь — доказательство «скилл в стойке не блокирован».
	var sc: Node = load("res://Logic/SpellCasterComponent.gd").new()
	sc.name = "SpellCasterComponent"
	player.add_child(sc)
	var arm := Node3D.new()
	arm.name = "SpringArm3D"
	player.add_child(arm)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	arm.add_child(cam)

	# Ловля сигналов groove_hit (данные попапов BardGrooveUI).
	var hits := []
	groove.groove_hit.connect(func(vd, src, d): hits.append([vd, src, d]))

	# Автолоады при -s ненадёжны — get-or-make (паттерн probe_bard_flow);
	# component ищет cond по /root/RhythmConductor → корень-чайлд с тем же именем.
	var cond = _get_or_make("res://Logic/RhythmConductor.gd", "RhythmConductor")
	_get_or_make("res://Graphics/AudioManager.gd", "AudioManager")
	var md = _get_or_make("res://Graphics/MusicDirector.gd", "MusicDirector")
	if md != null and "_combat_stream" in md:
		md._combat_stream = null  # чужой боевой луп не дёргает PLL (квирк)
	_check("cond get-or-make", cond != null)
	if cond == null:
		quit(1)
		return
	await process_frame  # settle автолоадов/UI
	cond.start(120.0)
	cond.stop()  # часы заморожены; song_time пишем руками
	_check("beat_len 0.5 при 120 BPM", absf(float(cond.beat_len) - 0.5) < 0.001)

	# ═══ S1: вход — старт 25%, tier 0, купол 100 ═══════════════════════════
	groove._on_stance_entered({}, "bard_groove")
	_check("S1 вход: is_active", bool(groove.is_active))
	_check("S1 groove=25", absf(float(groove.groove) - 25.0) < 0.01)
	_check("S1 tier=0", int(groove.tier) == 0)
	_check("S1 barrier=100", int(groove.barrier) == 100)
	_check("S1 лимит ~16 с", absf(float(groove.max_duration_left()) - 16.0) < 0.05)

	# ═══ S2: спад до 0 → выход groove_empty (детерминированный _process) ═══
	groove.groove = 0.01
	groove._process(1.0)
	_check("S2 выход groove_empty", not bool(groove.is_active) \
			and str(groove.last_exit_reason) == "groove_empty")
	_check("S2 groove обнулён", absf(float(groove.groove)) < 0.001)

	# ═══ S3: perfect-скилл в бит: +18, tier 1, купол +10, буфы DR/RR ═══════
	_re_enter(groove, cond)
	cond.song_time = 1.0  # frac=0 → dt=0 → perfect, beat_idx=2
	var v: String = groove.evaluate_action("skill")
	_check("S3 verdict perfect", v == "perfect")
	_check("S3 groove 25+18=43", absf(float(groove.groove) - 43.0) < 0.01)
	_check("S3 tier=1 (порог 40)", int(groove.tier) == 1)
	_check("S3 barrier 110 (perfect +10)", int(groove.barrier) == 110)
	_check("S3 DR буф = DR[1]", absf(float(hp_stub.damage_reduction) - float(G.DR[1])) < 0.001)
	_check("S3 RR буф = RR[1]", absf(float(hp_stub.reflect_ratio) - float(G.RR[1])) < 0.001)
	_check("S3 groove_hit сигнал (perfect, skill, +18)",
			hits.size() == 1 and hits[0][0] == "perfect" and hits[0][1] == "skill" \
			and absf(float(hits[0][2]) - 18.0) < 0.01)

	# ═══ S4: 3 действия в один бит = 1 заряд (анти-абуз last_charged_beat) ══
	var v4a: String = groove.evaluate_action("skill")
	var v4b: String = groove.evaluate_action("move")
	_check("S4 вердикт perfect вернулся (не блок)", v4a == "perfect" and v4b == "perfect")
	_check("S4 groove не вырос (43)", absf(float(groove.groove) - 43.0) < 0.01)
	_check("S4 barrier не вырос (110)", int(groove.barrier) == 110)

	# ═══ S5: движение в бит: move-тариф +12 ════════════════════════════════
	cond.song_time = 2.0  # beat 4 свежий
	var v5: String = groove.evaluate_action("move")
	_check("S5 move perfect +12 → 55", v5 == "perfect" \
			and absf(float(groove.groove) - 55.0) < 0.01)

	# ═══ S6: good-окно (dt=0.11): +10 ══════════════════════════════════════
	cond.song_time = 1.61  # frac=0.11 → good, beat 3 свежий
	var v6: String = groove.evaluate_action("skill")
	_check("S6 good +10 → 65", v6 == "good" and absf(float(groove.groove) - 65.0) < 0.01)

	# ═══ S7: fireball в бит: damage_mult>1.0, скилл НЕ блокирован ══════════
	cond.song_time = 2.5  # beat 5 свежий → perfect
	var ctx := {"damage_mult": 1.0}
	sc._groove_judge(player, "fireball", ctx)
	_check("S7 verdict попал в context", str(ctx.get("groove_verdict")) == "perfect")
	_check("S7 damage_mult > 1.0", float(ctx.get("damage_mult")) > 1.0)
	_check("S7 damage_mult = TIER_DAMAGE_MULT[tier]",
			absf(float(ctx.get("damage_mult")) - float(G.TIER_DAMAGE_MULT[int(groove.tier)])) < 0.001)
	_check("S7 judge зарядил +18 → 83", absf(float(groove.groove) - 83.0) < 0.01)
	_check("S7 tier=2 (порог 70)", int(groove.tier) == 2)
	cond.song_time = 3.0  # бит 6 свежий (бит 5 уже съеден judge-вызовом выше)
	sc.cast_skill("fireball")  # реальный путь; judge внутри
	_check("S7 cast_skill не заблокирован (заряд через полный каст)",
			absf(float(groove.groove) - 100.0) < 0.01)  # 83+18 → кап 100
	_check("S7 tier=3 (порог 95 на 100)", int(groove.tier) == 3)

	# ═══ S8: offbeat-скилл: без заряда/множителя, скилл НЕ блокирован ══════
	cond.song_time = 1.25  # frac=0.25 → dt=0.25 → offbeat
	var ctx8 := {"damage_mult": 1.0}
	var v8: String = groove.evaluate_action("skill")
	sc._groove_judge(player, "fireball", ctx8)
	_check("S8 offbeat вердикт", v8 == "offbeat")
	_check("S8 offbeat: groove не вырос", absf(float(groove.groove) - 100.0) < 0.01)
	_check("S8 offbeat: damage_mult НЕ изменён", float(ctx8.get("damage_mult")) == 1.0)

	# ═══ S9: спам сабами мимо бита (шаг <0.30 с): −6 за вызов, tier не растёт ═
	cond.song_time = 1.35  # dt=0.15 → offbeat
	groove.evaluate_action("sub")   # первый — таймер стартует, без штрафа
	groove.evaluate_action("sub")   # −6
	var g9 := float(groove.groove)
	groove.evaluate_action("sub")   # ещё −6
	_check("S9 спам: −6 за вызов (100→94→88)", absf(g9 - 94.0) < 0.01 \
			and absf(float(groove.groove) - 88.0) < 0.01)
	_check("S9 tier НЕ вырос", int(groove.tier) == 3)

	# ═══ S10: купол: перехват урона → barrier_break при срыве ══════════════
	var absorbed: bool = groove.player_damage_hook(999, null)
	_check("S10 урон перехвачен куполом", absorbed)
	_check("S10 выход barrier_break", not bool(groove.is_active) \
			and str(groove.last_exit_reason) == "barrier_break")

	# ═══ S11: потолок 16 с (elapsed-паттерн Потока, без стеночного ожидания) ═
	_re_enter(groove, cond)
	groove._elapsed = 15.999
	groove._process(0.01)
	_check("S11 выход max_duration", not bool(groove.is_active) \
			and str(groove.last_exit_reason) == "max_duration")

	# ═══ S12: UI-оверлей жив (groove_hit подключён, _ready прошёл) ═════════
	_check("S12 BardGrooveUI инстанс валиден", is_instance_valid(ui))

	print("ИТОГ: %d чеков, FAIL=%d" % [_count, _fails])
	quit(0 if _fails == 0 else 1)

func _get_or_make(script_path: String, node_name: String) -> Node:
	var n = root.get_node_or_null(node_name)
	if n != null:
		return n
	n = load(script_path).new()
	n.name = node_name
	root.add_child(n)
	return n

func _re_enter(groove: Node, cond: Node) -> void:
	## Прямой вход в стойку (без StanceComponent): компонент сам подключается
	## к cond (start, если не запущен) — после этого снова замораживаем часы.
	groove._on_stance_entered({}, "bard_groove")
	cond.stop()
	cond.song_time = 0.0

func _check(name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("PASS %s" % name)
	else:
		_fails += 1
		print("FAIL %s" % name)
