extends RefCounted

## Группировка скиллов магазина по веткам (Q50 Шаг 2, PRP
## tasks/q50_q51_admin_branches.md). Порядок секций — по order из
## Data/skill_branches.json (SkillBranchDB.get_branches); «Разное» — всегда
## последняя секция; пустые ветки не рисуются (заголовок без контента
## бесполезен). SkillMenu рисует заголовок секции + свой грид карточек.

const BRDB := preload("res://Logic/Skills/SkillBranchDB.gd")


static func grouped(skills: Dictionary) -> Array:
	## [{id: String, name: String, icon: String, skills: Array[Resource]}].
	## skills — словарь get_shop_skills(); раскладка по s.branch
	## ("" → «Разное»).
	var sections: Array = []
	var index := {}
	for b in BRDB.get_branches():
		var sec := {"id": b["id"], "name": b["name"], "icon": b["icon"], "skills": []}
		sections.append(sec)
		index[b["id"]] = sec
	var misc_meta: Dictionary = BRDB.load_data().get("misc", {"name": "Разное", "icon": "📦"})
	var misc := {"id": "", "name": misc_meta.get("name", "Разное"), "icon": misc_meta.get("icon", "📦"), "skills": []}
	for sid in skills:
		var s = skills[sid]
		var sec = index.get(s.branch, misc)
		sec["skills"].append(s)
	sections.append(misc)
	var out: Array = []
	for sec in sections:
		if not sec["skills"].is_empty():
			out.append(sec)
	return out
