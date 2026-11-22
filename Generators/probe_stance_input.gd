extends SceneTree

## Probe Q16 Шаг 1 (PRP tasks/q16_stances_bard_prp.md): StanceComponent
## скелет + перехват ввода ActionBar. Гейт: стойка активна → клавиша-оверрайд
## исполняет под-скилл и НЕ вызывает обычный скилл слота; после exit слот
## работает как раньше; сигнал-тройка доходит до ActionBar; повторный вход
## игнорируется; все тронутые скрипты парсятся. EXIT 0 = PASS.

const StanceScript := preload("res://Logic/StanceComponent.gd")
const EnterStanceScript := preload("res://Logic/Skills/EnterStanceEffect.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")
const SKILL := preload("res://Logic/Skills/Skill.gd")
const ActionBarScript := preload("res://Graphics/ActionBar.gd")
const SpellCasterScript := preload("res://Logic/SpellCasterComponent.gd")

## Эффект-щуп: пишет meta на кастере (наблюдение execute headless).
const PROBE_EFFECT := 'extends "res://Logic/Skills/Effect.gd"\nfunc apply(caster: Node, _ctx: Dictionary) -> void:\n\tcaster.set_meta("%s", str(_ctx.get("stance_power", "-")))\n'
## Стаб игрока: Node3D-наследник (get_world_3d для _aim_context) + реплика
## PlayerController.use_skill + поля под SkillMenu-гварды.
const STUB_PLAYER := "extends CharacterBody3D\nvar unlocked_skills := {}\nvar skill_points := 10\nfunc use_skill(id: String) -> void:\n\tif not unlocked_skills.get(id, false):\n\t\treturn\n\tvar sc = get_node_or_null(\"SpellCasterComponent\")\n\tif sc:\n\t\tsc.cast_skill(id)\n"

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

func _mk_dyn(src: String):
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	return gs.new()

func _mk_skill(id: String, icon: String, meta_key: String) -> Resource:
	var s = SKILL.new()
	s.id = id
	s.skill_name = id
	s.icon = icon
	s.effects.append(_mk_dyn(PROBE_EFFECT % meta_key))
	return s

func _slot_by_label(bar, label: String):
	for slot in bar.slots:
		if str(slot.key_info.get("label", "")) == label:
			return slot
	return null

func _key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	return ev

func _run() -> void:
	print("=== PROBE: Q16 Шаг 1 — StanceComponent + перехват ActionBar ===")
	await process_frame

	# 0) Парс всех скриптов, затронутых Шагами 0–1
	for path in ["res://Logic/PlayerController.gd", "res://Graphics/SkillMenu.gd",
			"res://Graphics/ActionBar.gd", "res://Logic/SpellCasterComponent.gd",
			"res://Logic/StanceComponent.gd", "res://Logic/Skills/EnterStanceEffect.gd",
			"res://Logic/Skills/SkillDB.gd", "res://Logic/Skills/Skill.gd"]:
		var sc = load(path)
		_ck(sc != null and sc.can_instantiate(), "парс %s" % path)

	# 1) Стаб игрока + компоненты + регистрация probe-скиллов
	var player = _mk_dyn(STUB_PLAYER)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	arm.add_child(cam)
	player.add_child(arm)
	var sc_node := Node.new()
	sc_node.name = "SpellCasterComponent"
	sc_node.set_script(SpellCasterScript)
	player.add_child(sc_node)
	var stance := Node.new()
	stance.name = "StanceComponent"
	stance.set_script(StanceScript)
	player.add_child(stance)
	var bar := ActionBarScript.new()
	player.add_child(bar)
	root.add_child(player)
	await process_frame
	await process_frame  # deferred _hook_stance

	player.unlocked_skills["probe_normal"] = true
	player.unlocked_skills["probe_stance"] = true

	SDB._skills["probe_sub_a"] = _mk_skill("probe_sub_a", "🅰", "probe_cast_a")
	SDB._skills["probe_sub_b"] = _mk_skill("probe_sub_b", "🅱", "probe_cast_b")
	SDB._skills["probe_sub_c"] = _mk_skill("probe_sub_c", "🅲", "probe_cast_c")
	SDB._skills["probe_normal"] = _mk_skill("probe_normal", "🅝", "probe_normal_cast")
	var stance_skill = SKILL.new()
	stance_skill.id = "probe_stance"
	stance_skill.skill_name = "Проба стойки"
	stance_skill.icon = "🌀"
	var subs: Array[Dictionary] = [
		{"id": "probe_sub_a", "label": "А", "default_slot": "5"},
		{"id": "probe_sub_b", "label": "Б", "default_slot": "self"},
		{"id": "probe_sub_c", "label": "В", "default_slot": "ЛКМ"},
	]
	stance_skill.stance_sub_skills = subs
	# Эффекты скилла-стойки: вход (как в игре) + щуп «обычный скилл исполнен»
	var enter_eff = EnterStanceScript.new()
	enter_eff.stance_id = "probe_stance"
	enter_eff.duration = 4.0
	stance_skill.effects.append(enter_eff)
	stance_skill.effects.append(_mk_dyn(PROBE_EFFECT % "probe_stance_cast"))
	SDB._skills["probe_stance"] = stance_skill

	# Раскладка: слот 5 = обычный скилл, Q = скилл-стойка
	_slot_by_label(bar, "5").set_skill("probe_normal")
	_slot_by_label(bar, "Q").set_skill("probe_stance")

	# 2) Вход через EnterStanceEffect (как в игре)
	var eff = EnterStanceScript.new()
	eff.stance_id = "probe_stance"
	eff.duration = 4.0
	eff.apply(player, {})
	_ck(stance.is_active, "стойка активна после EnterStanceEffect.apply")
	_ck(stance.overrides.get("5", "") == "probe_sub_a", "дефолт-бинд 5 → probe_sub_a")
	_ck(stance.overrides.get("self", "") == "probe_sub_b", "дефолт-бинд self → probe_sub_b")
	_ck(stance.overrides.get("ЛКМ", "") == "probe_sub_c", "дефолт-бинд ЛКМ → probe_sub_c")

	# 3) Повторный вход игнорируется (одна стойка за раз)
	var other := {"stance_id": "other", "sub_skills": [{"id": "probe_sub_a", "label": "x", "default_slot": "5"}]}
	_ck(not stance.enter_stance(other), "повторный вход в другую стойку игнорируется")
	_ck(stance.stance_id == "probe_stance", "активная стойка не сменилась")

	# 4) Сигналы дошли до ActionBar: иконки подменены, mouse-слот подсвечен
	var slot5 = _slot_by_label(bar, "5")
	var slotQ = _slot_by_label(bar, "Q")
	var slotLMB = _slot_by_label(bar, "ЛКМ")
	_ck(slot5.label_skill.text == "🅰", "иконка слота 5 подменена (была 🅝)")
	_ck(slotQ.label_skill.text == "🅱", "self-слот Q показывает иконку под-приёма")
	_ck(slotLMB.color == Color(0.55, 0.25, 0.8, 0.85), "mouse-слот подсвечен")
	_ck(slotLMB.label_skill.text == "", "mouse-слот без иконки (по ТЗ спеца)")

	# 5) Заряд тикает, сигнал updated живой
	var upd := [0]
	stance.stance_updated.connect(func(_t, _c): upd[0] += 1)
	await process_frame
	await process_frame
	_ck(upd[0] > 0, "stance_updated тикает")
	_ck(stance.charge > 0.0, "заряд растёт")

	# 6) ПЕРЕХВАТ клавиши: под-приём исполняется, обычный скилл слота — НЕТ
	bar._unhandled_input(_key_event(KEY_5))
	_ck(player.get_meta("probe_cast_a", "нет") == "1.0", "KEY_5 → probe_sub_a исполняется (power 1.0)")
	_ck(not player.has_meta("probe_normal_cast"), "обычный скилл слота 5 НЕ вызван")

	bar._unhandled_input(_key_event(KEY_Q))
	_ck(player.get_meta("probe_cast_b", "нет") == "1.0", "KEY_Q (self) → probe_sub_b")
	_ck(not player.has_meta("probe_stance_cast"), "обычный скилл стойки (Q) НЕ вызван")

	# 7) Перехват мыши (пустой mouse-слот тоже перехватывается)
	var evm := InputEventMouseButton.new()
	evm.button_index = MOUSE_BUTTON_LEFT
	evm.pressed = true
	bar._input(evm)
	_ck(player.get_meta("probe_cast_c", "нет") == "1.0", "ЛКМ → probe_sub_c (mouse-путь)")

	# 8) Выход: возврат иконок, слот работает как раньше
	stance.exit_stance("probe")
	_ck(not stance.is_active, "exit_stance деактивирует")
	_ck(slot5.label_skill.text == "🅝", "иконка слота 5 возвращена")
	_ck(slotLMB.color == Color(0.1, 0.1, 0.1, 0.7), "подсветка mouse-слота снята")
	bar._unhandled_input(_key_event(KEY_5))
	_ck(player.has_meta("probe_normal_cast"), "после exit KEY_5 кастует обычный скилл")
	_ck(not stance.try_handle_slot("5"), "try_handle_slot после exit = false")

	# 9) Q после exit → обычный путь → новый вход стойки (skill.execute)
	bar._unhandled_input(_key_event(KEY_Q))
	_ck(stance.is_active, "Q после exit снова входит в стойку (обычный путь)")
	_ck(player.has_meta("probe_stance_cast"), "скилл-стойка исполнился целиком")
	stance.exit_stance("probe_end")

	# Cleanup
	for pid in ["probe_sub_a", "probe_sub_b", "probe_sub_c", "probe_normal", "probe_stance"]:
		SDB._skills.erase(pid)
	player.queue_free()

	if _fail == 0 and _pass > 0:
		print("STANCE INPUT GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("STANCE INPUT GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
