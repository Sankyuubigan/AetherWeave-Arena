extends SceneTree

## UI-зонд Шага 3 Q36 «Кузница скиллов»: автолоад окна, жизненный цикл
## (open/close), создание/правка/удаление пользовательского скилла через
## форму, JSON на диске, живой реестр SkillDB. Запуск headless:
## & "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/probe_skill_forge_ui.gd

const USDB := preload("res://Logic/Skills/UserSkillDB.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")

var _fails := 0
var _count := 0


func _ck(cond: bool, label: String) -> void:
    _count += 1
    if cond:
        print("  PASS: %s" % label)
    else:
        _fails += 1
        print("  FAIL: %s" % label)


func _init() -> void:
    print("=== PROBE SKILL FORGE UI (Q36 Шаг 3) ===")
    _run()


func _run() -> void:
    var gpath := ProjectSettings.globalize_path(USDB.SAVE_PATH)
    if FileAccess.file_exists(USDB.SAVE_PATH):
        DirAccess.remove_absolute(gpath)

    await process_frame
    var win = root.get_node_or_null("SkillForgeWindow")
    _ck(win != null, "автолоад /root/SkillForgeWindow загружен")
    if win == null:
        _finish()
        return
    _ck(win.is_open == false, "при старте окно скрыто (is_open=false)")

    # Жизненный цикл
    win.open()
    _ck(win.is_open == true, "open(): is_open=true")
    _ck(win.visible == true, "open(): visible=true")

    # Создание через форму (тип по умолчанию — spawn_projectile)
    win._name.text = "Тест огня"
    win._on_create()
    var lst = USDB.list()
    _ck(lst.size() == 1, "JSON на диске: 1 скилл")
    var id0 := str(lst[0].get("id", "")) if lst.size() > 0 else ""
    _ck(id0.begins_with("user_"), "id с префиксом user_")
    _ck(SDB.get_skills().has(id0), "скилл в реестре сразу после создания")
    _ck(lst.size() > 0 and str(lst[0].get("name")) == "Тест огня", "имя записано")
    var f = FileAccess.open(USDB.SAVE_PATH, FileAccess.READ)
    var parsed = JSON.parse_string(f.get_as_text())
    f = null
    _ck(typeof(parsed) == TYPE_DICTIONARY and parsed.get("skills", []) is Array,
        "custom_skills.json — валидный JSON")

    # Правка: загрузить в форму, поменять цену, сохранить под тем же id
    win.load_from_dict(lst[0])
    win._price.value = 7
    win._on_create()
    lst = USDB.list()
    _ck(lst.size() == 1, "правка не создала дубль в файле")
    _ck(lst.size() > 0 and int(lst[0].get("price")) == 7, "цена обновлена")
    _ck(SDB.get_skills().get(id0) != null and SDB.get_skills().get(id0).price == 7,
        "реестр перезаписан через replace")

    # Смена типа: телепорт-скилл создаётся и валиден в реестре
    win._edit_id = ""
    win._set_type("teleport")
    win._name.text = "Рывок"
    win._on_create()
    lst = USDB.list()
    _ck(lst.size() == 2, "второй скилл добавлен в файл")
    var tp_id := ""
    for d in lst:
        if str(d.get("name", "")) == "Рывок":
            tp_id = str(d.get("id", ""))
    _ck(tp_id.begins_with("user_"), "телепорт-скилл сохранён")
    var s2 = SDB.get_skills().get(tp_id)
    _ck(s2 != null and s2.effects.size() >= 1, "телепорт-скилл в реестре с эффектом")

    # Удаление (как делает SkillForgeList)
    _ck(USDB.delete_skill(id0) == true, "delete_skill")
    SDB.unregister(id0)
    _ck(not SDB.get_skills().has(id0), "реестр чист после удаления")
    _ck(USDB.list().size() == 1, "в файле остался только телепорт")

    # Закрытие
    win.close()
    _ck(win.is_open == false, "close(): is_open=false")
    _ck(win.visible == false, "close(): visible=false")

    # Cleanup — не оставлять тестовые скиллы реальной игре
    DirAccess.remove_absolute(gpath)
    _ck(not FileAccess.file_exists(USDB.SAVE_PATH), "тестовый файл удалён (чисто для игры)")
    _finish()


func _finish() -> void:
    if _fails == 0 and _count > 0:
        print("SKILL FORGE UI GATE ALL PASS (%d чеков)" % _count)
        quit(0)
    else:
        print("SKILL FORGE UI GATE FAILED (%d/%d)" % [_fails, _count])
        quit(1)
