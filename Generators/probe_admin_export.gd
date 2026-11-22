extends SceneTree

## Probe Q50/Q51 Шаг 3 (PRP tasks/q50_q51_admin_branches.md): экспорт дампа.
## Гейт: дамп покрывает ВСЕ скиллы, ветка/под-приём/кирпичи-эффекты на месте,
## файл пишется и читается назад (JSON round-trip). EXIT 0 = PASS.

const EXP := preload("res://Generators/export_skills_json.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")

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
	print("=== PROBE: Q50/Q51 Шаг 3 — экспорт дампа скиллов ===")
	await process_frame

	var dump := EXP.build_dump()
	var all := SDB.get_skills()
	_ck(dump["skills"].size() == all.size(), "дамп покрывает все скиллы (%d)" % all.size())
	_ck(dump["branches"].size() >= 5, "ветки в дампе (%d)" % dump["branches"].size())
	var by_id := {}
	for s in dump["skills"]:
		by_id[s["id"]] = s
	_ck(by_id.has("fireball") and by_id["fireball"]["branch"] == "elemental",
		"fireball: ветка elemental в дампе")
	_ck(by_id["fireball"]["name"] == "Огненный Шар", "имя-отображение в дампе")
	_ck(by_id.has("bard_flow") and by_id["bard_flow"]["effects"].has("EnterStanceEffect"),
		"кирпичи-эффекты видны (EnterStanceEffect у bard_flow)")
	_ck(by_id["bard_drop"]["is_sub_skill"] == true, "под-приём помечен is_sub_skill")
	_ck(by_id["fireball"]["price"] >= 0, "цена на месте")

	var rc := EXP.write_dump("res://temp/skills_dump.json")
	_ck(rc == 0 and FileAccess.file_exists("res://temp/skills_dump.json"), "файл дампа записан")
	var rf := FileAccess.open("res://temp/skills_dump.json", FileAccess.READ)
	var back = JSON.parse_string(rf.get_as_text())
	rf.close()
	_ck(back is Dictionary and back["skills"].size() == all.size(),
		"JSON читается назад, размер совпадает")
	_ck(back is Dictionary and back["skills"][0].has("branch"), "round-trip: поле branch сохранилось")

	print("=== ИТОГ: %d PASS / %d FAIL ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
