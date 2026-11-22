extends SceneTree

## Probe Q50 Шаг 1 (PRP tasks/q50_q51_admin_branches.md): слой данных веток.
## Гейт: поле Skill.branch; ядро apply_overrides (rename/branch/clamp/
## негативы: фантом-скилл, неизвестная ветка); загрузка реального
## Data/skill_branches.json (ветки на месте, оверрайды применились,
## логика/эффекты не тронуты). EXIT 0 = PASS.

const SKILL := preload("res://Logic/Skills/Skill.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")
const BRDB := preload("res://Logic/Skills/SkillBranchDB.gd")

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
	print("=== PROBE: Q50 Шаг 1 — слой данных веток ===")
	await process_frame

	print("--- секция 1: дефолт поля ---")
	var sk = SKILL.new()
	_ck(sk.branch == "", "Skill.branch по умолчанию \"\"")

	print("--- секция 2: валидация _valid_overrides + ядро apply_overrides ---")
	var skills := {}
	for sid in ["a", "b"]:
		var s = SKILL.new()
		s.id = sid
		s.skill_name = "Старое имя"
		s.icon = "·"
		skills[sid] = s
	var raw_overrides := {
		"a": {"skill_name": "Новое имя", "branch": "br1"},
		"b": {"skill_name": "ххххххххххххххххххххххххххххххххххххххххх", "icon": "123456789", "branch": "ghost"},
		"ghost_skill": {"skill_name": "фантом"},
	}
	var branches_seed := [{"id": "br1", "name": "Тест", "icon": "T", "order": 1}]
	var valid: Dictionary = BRDB._valid_overrides(raw_overrides, branches_seed)
	_ck(valid["a"].skill_name == "Новое имя" and valid["a"].branch == "br1",
		"валидатор: rename + ветка прошли")
	_ck(valid["b"].skill_name.length() == 32, "валидатор: имя зажато до 32")
	_ck(valid["b"].icon.length() == 8, "валидатор: иконка зажата до 8")
	_ck(not valid["b"].has("branch"), "валидатор: неизвестная ветка отброшена")
	_ck(valid.has("ghost_skill"), "валидатор: фантом-скилл проходит (скиллы проверяет applier)")
	var n := BRDB.apply_overrides(skills, {"overrides": valid})
	_ck(n == 2, "applier: фантом-скилл пропущен, применено 2")
	_ck(skills["a"].skill_name == "Новое имя", "rename применён")
	_ck(skills["a"].branch == "br1", "ветка применена")
	_ck(skills["b"].skill_name.length() == 32, "зажатое имя дошло до скилла")
	_ck(skills["b"].branch == "", "скилл b остался в «Разном»")

	print("--- секция 2b: валидация _valid_misc (переименуемая «Разное», вердикт юзера) ---")
	var vm := BRDB._valid_misc({"name": "х".repeat(40), "icon": "123456789"})
	_ck(vm["name"].length() == 32, "misc: имя зажато до 32")
	_ck(vm["icon"].length() == 8, "misc: иконка зажата до 8")
	_ck(BRDB._valid_misc({})["name"] == "Разное", "misc: пустое → дефолт «Разное»")
	_ck(BRDB._valid_misc({"name": "Прочее"})["name"] == "Прочее", "misc: rename проходит")
	_ck(BRDB._valid_misc("мусор")["name"] == "Разное", "misc: не словарь → дефолт без краша")

	print("--- секция 3: реальный файл Data/skill_branches.json ---")
	var data_real: Dictionary = BRDB.load_data()
	var branches: Array = data_real["branches"]
	_ck(branches.size() >= 5, "веток ≥ 5 (стихийная/скрытность/астральная/некро/бард)")
	var ids := {}
	for b in branches:
		ids[b["id"]] = true
	_ck(ids.has("elemental") and ids.has("bard"), "elemental и bard в реестре")
	var sorted := BRDB.get_branches()
	_ck(sorted.size() == branches.size() and int(sorted[0]["order"]) <= int(sorted[sorted.size() - 1]["order"]),
		"get_branches отсортирован по order")
	var all := SDB.get_skills()
	var fb = all.get("fireball")
	_ck(fb != null and fb.branch == "elemental", "fireball в ветке elemental")
	_ck(all.get("bard_flow") != null and all["bard_flow"].branch == "bard", "bard_flow в ветке bard")
	_ck(all.get("double_jump") != null and all["double_jump"].branch == "", "double_jump в «Разном»")
	_ck(fb != null and fb.effects.size() > 0, "метаданные не тронули эффекты fireball")
	_ck(all["bard_flow"].effects.size() > 0, "эффекты bard_flow на месте")
	_ck(all["bard_flow"].skill_name == "Поток Гармонии", "имя без rename не изменено")
	_ck(not str(data_real["misc"]["name"]).is_empty(), "misc-секция читается из файла (имя не пустое)")

	print("=== ИТОГ: %d PASS / %d FAIL ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
