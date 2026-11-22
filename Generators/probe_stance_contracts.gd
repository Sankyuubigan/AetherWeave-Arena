extends SceneTree

## Probe Q16 Шаг 0 (PRP tasks/q16_stances_bard_prp.md): контракты данных стоек.
## Гейт: is_sub_skill/stance_sub_skills в Skill.gd; сериализатор Кузницы
## игнорирует новые поля (user не может создать стойку); под-скилл в SkillDB
## виден в get_skills, но отфильтрован из магазина (get_shop_skills).
## EXIT 0 = PASS.

const SKILL := preload("res://Logic/Skills/Skill.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")
const SER := preload("res://Logic/Skills/SkillSerializer.gd")
const USDB := preload("res://Logic/Skills/UserSkillDB.gd")

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
	print("=== PROBE: Q16 Шаг 0 — контракты данных стоек ===")
	await process_frame
	print("--- секция 1: дефолты полей ---")

	# 1) Дефолты новых полей
	var sk = SKILL.new()
	_ck(sk.is_sub_skill == false, "Skill.is_sub_skill по умолчанию false")
	_ck(sk.stance_sub_skills.is_empty(), "Skill.stance_sub_skills по умолчанию []")

	# 2) Сериализатор Кузницы не знает новых полей (user не может создать стойку)
	print("--- секция 2: сериализатор ---")
	var evil = SKILL.new()
	evil.id = "user_evil"
	evil.skill_name = "Попытка стойки"
	evil.icon = "✨"
	evil.is_sub_skill = true
	var subs: Array[Dictionary] = [{"id": "x", "label": "X", "default_slot": "1"}]
	evil.stance_sub_skills = subs
	var aoe = load("res://Logic/Skills/AoeDamageEffect.gd").new()
	aoe.radius = 3.0
	aoe.damage = 10
	evil.effects.append(aoe)
	var d = SER.skill_to_dict(evil)
	_ck(not d.has("is_sub_skill"), "skill_to_dict не пишет is_sub_skill")
	_ck(not d.has("stance_sub_skills"), "skill_to_dict не пишет stance_sub_skills")
	var restored = SER.skill_from_dict(d)
	_ck(restored != null, "round-trip валиден")
	if restored != null:
		_ck(restored.is_sub_skill == false, "round-trip: is_sub_skill сброшен в false")
		_ck(restored.stance_exit_on_sub == false, "round-trip: stance_exit_on_sub сброшен в false")
		_ck(restored.stance_sub_skills.is_empty(), "round-trip: stance_sub_skills пуст")

	# 3) Кузница отклоняет id без префикса user_ (подменить под-приём нельзя)
	_ck(USDB.save_skill({"id": "mana_crush", "name": "Подмена", "effects": []}) == false,
		"save_skill отклоняет id без префикса user_")

	# 4) Под-скилл в реестре, но НЕ в магазине. Базовые скиллы живут в
	# get_skills() напрямую; register/replace/unregister — гвард user_ Кузницы,
	# поэтому probe инъектирует dummy в статический реестр как базовый.
	# Базлайн магазина ДО инъекции: после Шагов 2/6 в реестре живут
	# под-приёмы (is_sub_skill) — магазин всегда меньше реестра на их число.
	var shop_before := SDB.get_shop_skills().size()
	var dummy = SKILL.new()
	dummy.id = "probe_sub_dummy"
	dummy.skill_name = "Проба под-приёма"
	dummy.icon = "🧪"
	dummy.is_sub_skill = true
	SDB._skills["probe_sub_dummy"] = dummy
	_ck(SDB.get_skills().has("probe_sub_dummy"), "под-скилл зарегистрирован в SkillDB")
	var shop = SDB.get_shop_skills()
	_ck(not shop.has("probe_sub_dummy"), "под-скилл отфильтрован из магазина")
	_ck(shop.has("fireball"), "обычные скиллы в магазине на месте")
	_ck(shop.size() == shop_before, "размер магазина не изменился (только dummy отфильтрован)")

	# 5) Обычный скилл остаётся в магазине
	var dummy2 = SKILL.new()
	dummy2.id = "probe_regular_dummy"
	dummy2.skill_name = "Обычный"
	dummy2.icon = "🧪"
	dummy2.price = 1
	SDB._skills["probe_regular_dummy"] = dummy2
	_ck(SDB.get_shop_skills().has("probe_regular_dummy"), "обычный скилл виден в магазине")

	# Cleanup
	SDB._skills.erase("probe_sub_dummy")
	SDB._skills.erase("probe_regular_dummy")
	_ck(not SDB.get_skills().has("probe_sub_dummy"), "dummy удалён (чисто)")

	# 6) exit_on_sub (вердикт юзера 22.11.26): приём = разряд стойки (мана).
	print("--- секция 6: exit_on_sub ---")
	_ck(SKILL.new().stance_exit_on_sub == false, "Skill.stance_exit_on_sub по умолчанию false")
	_ck(SDB.get_skills().get("mana_concentration").stance_exit_on_sub == true,
			"SkillDB: mana_concentration.stance_exit_on_sub = true")
	_ck(SDB.get_skills().get("bard_flow").stance_exit_on_sub == false,
			"SkillDB: bard_flow.stance_exit_on_sub = false")
	# Runtime: перехват кастует под-приём и закрывает стойку при exit_on_sub=true.
	var stub2 := GDScript.new()
	stub2.source_code = "extends CharacterBody3D\n"
	stub2.reload()
	var pl2 := CharacterBody3D.new()
	pl2.set_script(stub2)
	root.add_child(pl2)
	var sc_src := GDScript.new()
	sc_src.source_code = """
extends Node
var calls := []
func cast_skill(id: String, _ctx: Dictionary) -> void:
	calls.append(id)
"""
	sc_src.reload()
	var caster2 := Node.new()
	caster2.name = "SpellCasterComponent"
	caster2.set_script(sc_src)
	pl2.add_child(caster2)
	var st2 = load("res://Logic/StanceComponent.gd").new()
	st2.name = "StanceComponent"
	pl2.add_child(st2)
	var reasons: Array = []
	st2.stance_exited.connect(func(r): reasons.append(str(r)))
	st2.enter_stance({"stance_id": "probe_mana", "stance_skill_id": "probe_mana",
			"duration": 9.0, "exit_on_sub": true,
			"sub_skills": [{"id": "probe_sub1", "label": "A", "default_slot": "ЛКМ"}]})
	_ck(st2.is_active, "exit_on_sub=true: стойка вошла")
	_ck(st2.try_handle_slot("ЛКМ"), "exit_on_sub=true: перехват сработал")
	_ck(caster2.calls.size() == 1 and str(caster2.calls[0]) == "probe_sub1",
			"exit_on_sub=true: под-приём кастован")
	_ck(not st2.is_active and reasons.size() == 1 and str(reasons[0]) == "sub_used",
			"exit_on_sub=true: стойка закрылась (reason sub_used)")
	# false-ветка: Поток Барда — приём НЕ закрывает стойку.
	var st3 = load("res://Logic/StanceComponent.gd").new()
	st3.name = "StanceComponent2"
	pl2.add_child(st3)
	st3.enter_stance({"stance_id": "probe_bard", "stance_skill_id": "probe_bard",
			"duration": 9.0,
			"sub_skills": [{"id": "probe_sub1", "label": "A", "default_slot": "ЛКМ"}]})
	st3.try_handle_slot("ЛКМ")
	_ck(st3.is_active, "exit_on_sub=false (Поток): стойка живёт после приёма")
	st3.exit_stance("probe")

	if _fail == 0 and _pass > 0:
		print("STANCE CONTRACTS GATE ALL PASS (%d чеков)" % _pass)
		quit(0)
	else:
		print("STANCE CONTRACTS GATE FAILED (%d/%d)" % [_fail, _pass])
		quit(1)
