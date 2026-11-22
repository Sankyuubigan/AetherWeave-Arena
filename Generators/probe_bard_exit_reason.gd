extends SceneTree

## Probe раунд 3 (вердикт спеца 09, В.4.2 + В.6.3): причины выхода Потока.
## Каждая из 5 причин закрывает стойку с last_exit_reason + сигнал
## stance_exited(reason) + баннер BardFlowUI из EXIT_BANNERS (текст и
## жизнь 2.0 с → погасание). fuel_out — по кадрам _process; barrier_break —
## реальный путь урона игрока (player_damage_hook, купол dual-path);
## bard_drop — реальный self-пресс через гейт (kind "" без ритма) + эффект;
## cancel — Esc; max_duration — _flow_elapsed 13.999. Self-защита 0.45 с:
## пресс сразу после входа глотается ЦЕЛИКОМ. EXIT 0 = PASS.

const BardFlowUIScript := preload("res://Graphics/BardFlowUI.gd")

const STUB_PLAYER := "extends CharacterBody3D\nvar speed_mult: float = 1.0\n"
## Кастер-стаб probe_bard_flow: записи + исполнение эффектов SkillDB.
const CASTER_STUB := "extends Node\nvar calls := []\nfunc cast_skill(id, ctx):\n\tcalls.append([id, ctx])\n\tvar sk = load(\"res://Logic/Skills/SkillDB.gd\").get_skills().get(id)\n\tif sk != null:\n\t\tfor e in sk.effects:\n\t\t\te.apply(get_parent(), ctx)\n"

var _pass := 0
var _fail := 0
var exit_box := [""]

func _ck(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)

func _init() -> void:
	call_deferred("_run")

func _mk_dyn(src: String):
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	return gs.new()

func _get_or_make(script_path: String, node_name: String) -> Node:
	var n = root.get_node_or_null(node_name)
	if n != null:
		return n
	n = load(script_path).new()
	n.name = node_name
	root.add_child(n)
	return n

func _key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev

func _enter_bard(stance: Node) -> void:
	stance.enter_stance({
		"stance_id": "bard_flow",
		"stance_skill_id": "bard_flow",
		"duration": 99.0,
		"rhythm_gate": true,
		"sub_kinds": {"bard_note": "harmony", "bard_chord": "chord"},
		"sub_skills": [
			{"id": "bard_note", "label": "Ноты", "default_slot": "ЛКМ"},
			{"id": "bard_chord", "label": "Аккорд", "default_slot": "ПКМ"},
			{"id": "bard_drop", "label": "Дроп", "default_slot": "self"},
		],
	})

## Баннер ставится в UI._process на переходе is_flowing true→false.
func _check_banner(ui, text: String, label: String) -> void:
	var ok := false
	for i in 10:
		await process_frame
		if str(ui._banner_text) == text and float(ui._banner_left) > 0.0:
			ok = true
			break
	_ck(ok, label)

func _run() -> void:
	print("=== PROBE: раунд 3 — причины выхода Потока + баннеры (В.4.2) ===")
	await process_frame

	for path in ["res://Graphics/BardFlowUI.gd", "res://Logic/BardFlowComponent.gd",
			"res://Logic/StanceComponent.gd", "res://Logic/RhythmJudge.gd",
			"res://Logic/RhythmConductor.gd", "res://Logic/Skills/BardDropEffect.gd",
			"res://Logic/Skills/SkillDB.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)
	_ck(ResourceLoader.exists("res://Scenes/ball_lightning.tscn"),
			"сцена рикошета ball_lightning.tscn существует")

	var cond = _get_or_make("res://Logic/RhythmConductor.gd", "RhythmConductor")
	var judge = _get_or_make("res://Logic/RhythmJudge.gd", "RhythmJudge")
	await process_frame
	judge.conductor = cond
	judge.paused = false

	var player = _mk_dyn(STUB_PLAYER)
	player.name = "ExitReasonPlayer"
	var stance := Node.new()
	stance.name = "StanceComponent"
	stance.set_script(load("res://Logic/StanceComponent.gd"))
	player.add_child(stance)
	var flow := Node.new()
	flow.name = "BardFlowComponent"
	flow.set_script(load("res://Logic/BardFlowComponent.gd"))
	player.add_child(flow)
	var caster = _mk_dyn(CASTER_STUB)
	caster.name = "SpellCasterComponent"
	player.add_child(caster)
	var ui := BardFlowUIScript.new()
	ui.name = "BardFlowUI"
	player.add_child(ui)
	root.add_child(player)
	var enemy = _mk_dyn("extends Node3D\n")
	root.add_child(enemy)
	enemy.position = Vector3(0, 1.0, -8)
	stance.stance_exited.connect(func(r): exit_box[0] = r)
	await process_frame
	await process_frame

	# ── 1) fuel_out: топливо 0 → «ПОТОК СОРВАН (ритм потерян)» ────────────
	_enter_bard(stance)
	await process_frame
	_ck(stance.is_active, "вход Потока (fuel_out-сценарий)")
	_ck(ui._panel.visible, "UI Потока виден при активном Потоке")
	flow.fuel = -0.01
	await process_frame
	await process_frame
	_ck(not stance.is_active, "fuel_out закрыл стойку")
	_ck(str(flow.last_exit_reason) == "fuel_out", "last_exit_reason = fuel_out")
	_ck(exit_box[0] == "fuel_out", "stance_exited(reason) = fuel_out")
	await _check_banner(ui, "ПОТОК СОРВАН (ритм потерян)", "баннер fuel_out")
	ui._banner_left = 0.001
	await process_frame
	await process_frame
	_ck(float(ui._banner_left) <= 0.0 and not ui._panel.visible,
			"баннер погас, панель скрыта")

	# ── 2) max_duration: лимит → «ПОТОК ЗАВЕРШЁН (60 с)» (текст из консты) ──
	_enter_bard(stance)
	await process_frame  # UI обязан увидеть вход: баннер = переход true→false
	flow._flow_elapsed = float(flow.MAX_FLOW_DURATION) + 0.01
	await process_frame
	await process_frame
	_ck(not stance.is_active, "max_duration закрыл стойку (даже 100% Perfect)")
	_ck(str(flow.last_exit_reason) == "max_duration", "last_exit_reason = max_duration")
	_ck(exit_box[0] == "max_duration", "stance_exited(reason) = max_duration")
	await _check_banner(ui,
			"ПОТОК ЗАВЕРШЁН (%d с)" % int(round(float(flow.MAX_FLOW_DURATION))),
			"баннер max_duration (золотой)")
	ui._banner_left = 0.001
	await process_frame
	await process_frame

	# ── 3) barrier_break: реальный урон игрока → купол → «КУПОЛ РАЗБИТ!» ──
	_enter_bard(stance)
	await process_frame  # UI обязан увидеть вход: баннер = переход true→false
	var barrier0: int = int(flow.barrier)
	_ck(barrier0 > 0, "купол стоит (%d)" % barrier0)
	flow.player_damage_hook(150, enemy)  # dual-path урона игрока (нет HealthComponent)
	_ck(not stance.is_active, "купол пробит → стойка закрыта (синхронно)")
	_ck(str(flow.last_exit_reason) == "barrier_break", "last_exit_reason = barrier_break")
	_ck(exit_box[0] == "barrier_break", "stance_exited(reason) = barrier_break")
	await _check_banner(ui, "КУПОЛ РАЗБИТ!", "баннер barrier_break")
	ui._banner_left = 0.001
	await process_frame
	await process_frame

	# ── 4) bard_drop: self-защита → rewind → пресс → эффект → «БАС-ДРОП!» ─
	_enter_bard(stance)
	await process_frame
	var calls0: int = caster.calls.size()
	_ck(stance.try_handle_slot("self"), "self-пресс перехвачен стойкой")
	_ck(caster.calls.size() == calls0, "self-защита 0.45 с (В.6.3): каста НЕТ")
	stance._enter_usec = Time.get_ticks_usec() - 500000  # защита истекла
	_ck(stance.try_handle_slot("self"), "self-пресс после rewind проходит")
	_ck(caster.calls.size() == calls0 + 1 \
			and str(caster.calls[calls0][0]) == "bard_drop", "гейт: kind \"\" кастует bard_drop")
	_ck(not stance.is_active, "Бас-Дроп закрыл Поток")
	_ck(str(flow.last_exit_reason) == "bard_drop", "last_exit_reason = bard_drop")
	_ck(exit_box[0] == "bard_drop", "stance_exited(reason) = bard_drop")
	await _check_banner(ui, "ФИНАЛЬНЫЙ БАС-ДРОП!", "баннер bard_drop (фиолет-золото)")
	ui._banner_left = 0.001
	await process_frame
	await process_frame

	# ── 5) cancel: Esc → «ПОТОК ОТМЕНЁН» (UI-гард: окон нет) ──────────────
	_enter_bard(stance)
	await process_frame
	_ck(not stance._ui_open(), "UI-гард: окна закрыты → Esc пройдёт")
	stance._unhandled_input(_key_event(KEY_ESCAPE))
	_ck(not stance.is_active, "Esc отменил стойку")
	_ck(str(flow.last_exit_reason) == "cancel", "last_exit_reason = cancel")
	_ck(exit_box[0] == "cancel", "stance_exited(reason) = cancel")
	await _check_banner(ui, "ПОТОК ОТМЕНЁН", "баннер cancel (серый)")
	ui._banner_left = 0.001
	await process_frame
	await process_frame

	# Cleanup
	judge.reset()
	cond.stop()
	player.queue_free()
	enemy.queue_free()
	await process_frame

	if _fail == 0 and _pass > 0:
		print("BARD EXIT REASON GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("BARD EXIT REASON GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
