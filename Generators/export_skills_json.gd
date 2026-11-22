extends SceneTree

## Экспорт дампа скиллов для админки (Q50/Q51 Шаг 3, PRP
## tasks/q50_q51_admin_branches.md). Запуск (делает admin/start_admin.bat
## при каждом старте — свежесть гарантируется батником):
##   godot --headless -s res://Generators/export_skills_json.gd
## Выход: temp/skills_dump.json — ПОЛНЫЙ реестр скиллов (включая под-приёмы
## стоек) + ветки. Данные — только ЧТЕНИЕ кода: логика в SkillDB, админка
## правит лишь имя-отображение/ветку (Data/skill_branches.json).

const SDB := preload("res://Logic/Skills/SkillDB.gd")
const SER := preload("res://Logic/Skills/SkillSerializer.gd")
const BRDB := preload("res://Logic/Skills/SkillBranchDB.gd")
const OUT_PATH := "res://temp/skills_dump.json"


static func build_dump() -> Dictionary:
	## Поля скилла — через SkillSerializer.skill_to_dict (контракт Кузницы,
	## клампы те же); effects заменяются списком имён кирпичей (для показа
	## в админке:serializer знает только MVP-типы, здесь видны ВСЕ).
	var skills := SDB.get_skills()
	var list: Array = []
	for sid in skills:
		var s = skills[sid]
		var d := SER.skill_to_dict(s)
		d["is_sub_skill"] = bool(s.is_sub_skill)
		d["branch"] = str(s.branch)
		d["cooldown"] = float(s.cooldown)
		var bricks: Array = []
		for e in s.effects:
			var sc = e.get_script()
			if sc:
				bricks.append(str(sc.resource_path).get_file().get_basename())
		d["effects"] = bricks
		list.append(d)
	return {
		"generated": Time.get_datetime_string_from_system(),
		"branches": BRDB.get_branches(),
		"skills": list,
	}


static func write_dump(path: String) -> int:
	## Пишет дамп; 0 = ОК. Вызывается и батником, и probe_admin_export.
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[export] FAIL открыть %s, ошибка %d" % [path, FileAccess.get_open_error()])
		return 1
	f.store_string(JSON.stringify(build_dump(), "\t"))
	f.close()
	print("[export] дамп записан: %s" % path)
	return 0


func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	quit(write_dump(OUT_PATH))
