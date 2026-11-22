extends RefCounted

## Ветки умений (Q50, PRP tasks/q50_q51_admin_branches.md): метаданные поверх
## кода — имя-отображение и ветка скилла правятся из админки
## (admin/start_admin.bat) в Data/skill_branches.json. Логика и id скиллов
## остаются в SkillDB (код-ССОТ) — из JSON их изменить нельзя.
## Границы как у SkillSerializer: неизвестные id отбрасываются с логом, битый
## файл не валит игру (правило 3 PRP), имена/иконки зажимаются.

const DATA_PATH := "res://Data/skill_branches.json"
const NAME_MAX := 32
const ICON_MAX := 8
const DEFAULT_BRANCH := ""  # без записи в JSON → секция «Разное»
const DEFAULT_MISC := {"name": "Разное", "icon": "📦"}  # служебная секция, имя правится в JSON

static var _cache_branches: Array = []
static var _cache_overrides: Dictionary = {}
static var _cache_misc: Dictionary = {}
static var _cache_loaded := false


static func load_data() -> Dictionary:
	## Читает и валидирует Data/skill_branches.json.
	## Возвращает {branches: Array[Dictionary], overrides: Dictionary}.
	## Файл отсутствует/битый → пустые данные («Разное»), игра не валится.
	if _cache_loaded:
		return {"branches": _cache_branches, "overrides": _cache_overrides, "misc": _cache_misc}
	var branches: Array = []
	var overrides: Dictionary = {}
	var misc: Dictionary = DEFAULT_MISC.duplicate()
	if FileAccess.file_exists(DATA_PATH):
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				branches = _valid_branches(parsed.get("branches", []))
				overrides = _valid_overrides(parsed.get("overrides", {}), branches)
				misc = _valid_misc(parsed.get("misc", {}))
				print("[SkillBranchDB] загружено: %d веток, %d оверрайдов (%s)" % [branches.size(), overrides.size(), DATA_PATH])
			else:
				print("[SkillBranchDB] JSON битый (%s) — все скиллы в «Разное»" % DATA_PATH)
		else:
			print("[SkillBranchDB] файл не открыт (%s), ошибка %d" % [DATA_PATH, FileAccess.get_open_error()])
	else:
		print("[SkillBranchDB] %s отсутствует — все скиллы в «Разное»" % DATA_PATH)
	_cache_branches = branches
	_cache_overrides = overrides
	_cache_misc = misc
	_cache_loaded = true
	return {"branches": branches, "overrides": overrides, "misc": misc}


static func get_branches() -> Array:
	## Ветки в порядке order (для UI магазина и экспорта дампа).
	var branches: Array = load_data()["branches"].duplicate(true)
	branches.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return branches


static func apply_overrides(skills: Dictionary, data: Dictionary) -> int:
	## Ядро: накладывает оверрайды {id: {skill_name?, icon?, branch?}} на
	## словарь скиллов. Неизвестный id скилла — пропуск с логом (файл не валит).
	## Возвращает число применённых записей.
	var overrides: Dictionary = data.get("overrides", {})
	var applied := 0
	for sid in overrides:
		if not skills.has(sid):
			print("[SkillBranchDB] оверрайд для неизвестного скилла '%s' — пропущен" % sid)
			continue
		var s = skills[sid]
		var o: Dictionary = overrides[sid]
		if o.has("skill_name"):
			s.skill_name = o["skill_name"]
		if o.has("icon"):
			s.icon = o["icon"]
		if o.has("branch"):
			s.branch = o["branch"]
		applied += 1
	print("[SkillBranchDB] применено оверрайдов: %d/%d" % [applied, overrides.size()])
	return applied


static func apply_from_file(skills: Dictionary) -> int:
	## Хук SkillDB.get_skills(): оверрайды из Data/skill_branches.json.
	return apply_overrides(skills, load_data())


static func _valid_branches(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for b in raw:
			if b is Dictionary and str(b.get("id", "")) != "":
				out.append({
					"id": str(b.get("id")),
					"name": str(b.get("name", "")).substr(0, NAME_MAX),
					"icon": str(b.get("icon", "")).substr(0, ICON_MAX),
					"order": int(b.get("order", 100)),
				})
			else:
				print("[SkillBranchDB] ветка без id отброшена: %s" % str(b))
	else:
		print("[SkillBranchDB] branches не массив — список веток пуст")
	return out


static func _valid_misc(raw) -> Dictionary:
	## Служебная секция «без ветки» (Q51, вердикт юзера 22.11.26: «Разное»
	## должно переименовываться). name/icon клампятся; битое/пустое → дефолт.
	var out: Dictionary = DEFAULT_MISC.duplicate()
	if raw is Dictionary:
		var name := str(raw.get("name", "")).substr(0, NAME_MAX)
		var icon := str(raw.get("icon", "")).substr(0, ICON_MAX)
		if name != "":
			out["name"] = name
		if icon != "":
			out["icon"] = icon
	else:
		if raw != null:
			print("[SkillBranchDB] misc не словарь — имя секции по умолчанию («%s»)" % DEFAULT_MISC["name"])
	return out


static func _valid_overrides(raw, branches: Array) -> Dictionary:
	var ids := {}
	for b in branches:
		ids[b["id"]] = true
	var out: Dictionary = {}
	if raw is Dictionary:
		for sid in raw:
			var o = raw[sid]
			if not (o is Dictionary):
				print("[SkillBranchDB] оверрайд '%s' не словарь — отброшен" % str(sid))
				continue
			var entry := {}
			if o.has("skill_name"):
				entry["skill_name"] = str(o["skill_name"]).substr(0, NAME_MAX)
			if o.has("icon"):
				entry["icon"] = str(o["icon"]).substr(0, ICON_MAX)
			if o.has("branch"):
				var bid := str(o["branch"])
				if bid == "" or ids.has(bid):  # "" = явный «Разное» (сброс ветки)
					entry["branch"] = bid
				else:
					print("[SkillBranchDB] '%s': неизвестная ветка '%s' — ветка не применена" % [str(sid), bid])
			if not entry.is_empty():
				out[str(sid)] = entry
	else:
		print("[SkillBranchDB] overrides не словарь — оверрайдов нет")
	return out
