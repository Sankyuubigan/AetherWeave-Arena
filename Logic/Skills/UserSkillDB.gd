extends RefCounted

## Персист пользовательских скиллов Кузницы (Q36) — user://custom_skills.json.
## Прецедент формата: SkillPresetsPanel.gd (skill_presets.json). Все id с
## префиксом user_; встроенные id не перетираются (гейт в load_all + register
## в SkillDB). Вызывается SkillDB.get_skills() в конце ленивой инициализации.

const SERIALIZER := preload("res://Logic/Skills/SkillSerializer.gd")
const SAVE_PATH := "user://custom_skills.json"
const PREFIX := "user_"

static var _loaded := false


static func load_all(dict: Dictionary) -> int:
    ## Вливает сохранённые пользовательские скиллы в реестр dict.
    ## Возвращает число загруженных скиллов. Флаг _loaded не даёт дубль
    ## при повторном вызове (как _initialized в SkillDB).
    if _loaded:
        return 0
    _loaded = true
    if not FileAccess.file_exists(SAVE_PATH):
        return 0
    var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if f == null:
        _log("файл не открылся: %s" % SAVE_PATH)
        return 0
    var parsed = JSON.parse_string(f.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        _log("битый JSON (не словарь) — файл пропущен")
        return 0
    var skills = parsed.get("skills", null)
    if not (skills is Array):
        _log("нет массива skills — файл пропущен")
        return 0
    var n := 0
    for entry in skills:
        if not (entry is Dictionary):
            _log("запись не словарь — пропущена")
            continue
        var s = SERIALIZER.skill_from_dict(entry)
        if s == null:
            continue  # SkillSerializer уже залогировал причину
        if not s.id.begins_with(PREFIX):
            _log("id без префикса user_ — пропущен: %s" % s.id)
            continue
        if dict.has(s.id):
            _log("конфликт id с существующим скиллом — пропущен: %s" % s.id)
            continue
        dict[s.id] = s
        n += 1
        _log("загружен пользовательский скилл: %s" % s.id)
    return n


static func save_skill(d: Dictionary) -> bool:
    ## Сохраняет/перезаписывает пользовательский скилл в JSON.
    ## Валидация полная (через сериализатор) до записи на диск.
    var id := str(d.get("id", ""))
    if not id.begins_with(PREFIX):
        _log("save_skill: id без префикса user_ отклонён: %s" % id)
        return false
    if SERIALIZER.skill_from_dict(d) == null:
        return false  # сериализатор залогировал причину
    var skills := _read_raw()
    var replaced := false
    for i in skills.size():
        if str(skills[i].get("id", "")) == id:
            skills[i] = d
            replaced = true
    if not replaced:
        skills.append(d)
    _write_raw(skills)
    _log("сохранён пользовательский скилл: %s" % id)
    return true


static func delete_skill(id: String) -> bool:
    var skills := _read_raw()
    var before := skills.size()
    skills = skills.filter(func(e):
        return str(e.get("id", "")) != id)
    if skills.size() == before:
        return false
    _write_raw(skills)
    _log("удалён пользовательский скилл: %s" % id)
    return true


static func list() -> Array:
    ## Сырые словари сохранённых пользовательских скиллов (для списка UI).
    return _read_raw()


static func generate_id(name: String) -> String:
    ## Уникальный id: user_ + слаг имени (<=12) + хэш имени+время.
    var slug := ""
    for ch in name.to_lower():
        if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
            slug += ch
        elif slug != "" and slug.right(1) != "_":
            slug += "_"
    while slug.begins_with("_"):
        slug = slug.substr(1)
    slug = slug.substr(0, 12)
    if slug.ends_with("_"):
        slug = slug.substr(0, slug.length() - 1)
    if slug.is_empty():
        slug = "skill"
    var h := absi(hash(name + str(Time.get_ticks_msec()))) % 100000
    return "%s%s_%d" % [PREFIX, slug, h]


static func _read_raw() -> Array:
    if not FileAccess.file_exists(SAVE_PATH):
        return []
    var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if f == null:
        return []
    var parsed = JSON.parse_string(f.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return []
    var skills = parsed.get("skills", [])
    return skills if skills is Array else []


static func _write_raw(skills: Array) -> bool:
    var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if f == null:
        _log("запись не удалась: %s" % SAVE_PATH)
        return false
    f.store_string(JSON.stringify({"skills": skills}, "  "))
    return true


static func _log(msg: String) -> void:
    ## Консоль + лог в Logger-автолоад. Из статики имя автолоада резолвится
    ## в КЛАСС скрипта, а не в инстанс — инстанс берём через дерево сцен.
    print("UserSkillDB: %s" % msg)
    var ml := Engine.get_main_loop()
    if ml is SceneTree:
        var lg = (ml as SceneTree).root.get_node_or_null("/root/Logger")
        if lg != null:
            lg.log_message("UserSkillDB: %s" % msg)
