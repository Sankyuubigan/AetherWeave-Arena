extends SceneTree

## Гейт Шага 1 Q36 «Кузница скиллов»: round-trip сериализации, клампы, белые
## списки, register-гейт, персист JSON (QA-таблица PRP: #1 #2 #3 #4).
## Execute-гейт по манекену — Шаг 4 (добавляется сюда же).
## Запуск (headless):
## & "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/test_skill_forge.gd

const SER := preload("res://Logic/Skills/SkillSerializer.gd")
const USDB := preload("res://Logic/Skills/UserSkillDB.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")
const SKILL := preload("res://Logic/Skills/Skill.gd")

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
    print("=== TEST SKILL FORGE (Q36 Шаг 1) ===")
    # Чистый лист: убираем файл прошлых прогонов, чтобы get_skills() в этом
    # процессе проинициализировался без пользовательских скиллов.
    var gpath := ProjectSettings.globalize_path(USDB.SAVE_PATH)
    if FileAccess.file_exists(USDB.SAVE_PATH):
        DirAccess.remove_absolute(gpath)
    _test_roundtrip()
    _test_clamps()
    _test_whitelist()
    _test_register_gate()
    _test_persist()
    if _fails == 0 and _count > 0:
        print("SKILL FORGE GATE ALL PASS (%d чеков)" % _count)
        quit(0)
    else:
        print("SKILL FORGE GATE FAILED (%d/%d)" % [_fails, _count])
        quit(1)


func _mk_skill():
    ## Полный Skill со всеми 4 MVP-типами эффектов для round-trip.
    var s = SKILL.new()
    s.id = "user_roundtrip"
    s.skill_name = "Огненный тест"
    s.description = "Проверка сериализации"
    s.icon = "🔥"
    s.price = 3
    s.max_range = 120.0
    s.requires_target = true
    s.target_type = "enemy"
    s.cast_anim = "Throw"
    s.cast_time = 1.5
    s.alternate_hands = true
    s.cast_hand = "Left"
    s.shake = 0.5
    var proj = load("res://Logic/Skills/SpawnProjectileEffect.gd").new()
    proj.projectile_scene = load("res://Scenes/fireball.tscn")
    proj.spawn_from_hand = true
    proj.spawn_delay = 0.35
    proj.offset_y = 1.4
    proj.impact_shake = 0.4
    proj.impact_sound = load("res://Audio/SFX/neural_fireball.res")
    proj.decal_scale = 1.5
    proj.lava_pool = true
    s.effects.append(proj)
    var snd = load("res://Logic/Skills/PlaySoundEffect.gd").new()
    snd.audio_stream = load("res://Audio/SFX/neural_thunder.res")
    snd.volume_db = -6.0
    s.effects.append(snd)
    var hs = load("res://Logic/Skills/SpawnHitscanEffect.gd").new()
    hs.damage = 42
    hs.beam_color = Color(0.9, 0.15, 0.1)
    s.effects.append(hs)
    var aoe = load("res://Logic/Skills/AoeDamageEffect.gd").new()
    aoe.radius = 7.0
    aoe.damage = 25
    aoe.vfx_scene = load("res://Scenes/heart_burst.tscn")
    s.effects.append(aoe)
    return s


func _test_roundtrip() -> void:
    print("-- round-trip")
    var s1 = _mk_skill()
    var d1: Dictionary = SER.skill_to_dict(s1)
    var s2 = SER.skill_from_dict(d1)
    _ck(s2 != null, "from_dict вернул Skill")
    if s2 == null:
        _fails += 1
        return
    var d2: Dictionary = SER.skill_to_dict(s2)
    _ck(d2 == d1, "dict -> Skill -> dict без потерь")
    # Точечные проверки структуры (не только словарь целиком):
    _ck(s2.effects.size() == 4, "все 4 эффекта на месте")
    _ck(s2.price == 3 and s2.cast_time == 1.5 and s2.shake == 0.5, "числовые поля на месте")
    _ck(s2.cast_anim == "Throw" and s2.cast_hand == "Left", "анимация/рука на месте")
    var proj_back = null
    for e in s2.effects:
        var bn := str(e.get_script().resource_path.get_file().get_basename())
        if bn == "SpawnProjectileEffect":
            proj_back = e
    _ck(proj_back != null and proj_back.projectile_scene != null
        and proj_back.projectile_scene.resource_path == "res://Scenes/fireball.tscn",
        "сцена снаряда прошла круг (path preserved)")


func _test_clamps() -> void:
    print("-- клампы")
    var bad := {
        "id": "user_clamps",
        "name": "Крайние значения",
        "price": 500,
        "max_range": 5000.0,
        "cast_time": 99.0,
        "shake": 7.0,
        "cast_hand": "Center",
        "target_type": "nobody",
        "cast_anim": "Backflip",
        "effects": [
            {"type": "hitscan", "damage": 500},
            {"type": "aoe", "radius": 100.0, "damage": 999},
            {"type": "spawn_projectile", "scene": "res://Scenes/fireball.tscn",
                "spawn_delay": 5.0, "impact_shake": 3.0, "offset_y": 99.0},
            {"type": "play_sound", "stream": "res://Audio/SFX/neural_fireball.res",
                "volume_db": -100.0},
        ],
    }
    var s = SER.skill_from_dict(bad)
    _ck(s != null, "битые значения не ломают разбор")
    if s == null:
        _fails += 1
        return
    _ck(s.price == 10, "цена 500->10")
    _ck(s.max_range == 200.0, "дальность 5000->200")
    _ck(s.cast_time == 3.0, "cast_time 99->3")
    _ck(s.shake == 1.0, "тряска 7->1")
    _ck(s.cast_hand == "Right", "рука Center->Right (дефолт)")
    _ck(s.target_type == "enemy", "target_type nobody->enemy")
    _ck(s.cast_anim == "", "cast_anim Backflip->пусто")
    var hs = null
    var aoe = null
    var pr = null
    var snd = null
    for e in s.effects:
        match str(e.get_script().resource_path.get_file().get_basename()):
            "SpawnHitscanEffect": hs = e
            "AoeDamageEffect": aoe = e
            "SpawnProjectileEffect": pr = e
            "PlaySoundEffect": snd = e
    _ck(hs != null and hs.damage == 150, "урон hitscan 500->150")
    _ck(aoe != null and aoe.radius == 15.0, "радиус AoE 100->15")
    _ck(aoe != null and aoe.damage == 150, "урон AoE 999->150")
    _ck(pr != null and pr.spawn_delay == 1.0, "spawn_delay 5->1")
    _ck(pr != null and pr.impact_shake == 1.0, "impact_shake 3->1")
    _ck(pr != null and pr.offset_y == 2.0, "offset_y 99->2")
    _ck(snd != null and snd.volume_db == -30.0, "volume_db -100 -> -30")


func _test_whitelist() -> void:
    print("-- белые списки")
    var d := {
        "id": "user_wl",
        "name": "Белые списки",
        "effects": [
            {"type": "spawn_projectile", "scene": "res://Scenes/hack.tscn"},
            {"type": "aoe", "vfx": "res://Scenes/not_exists.tscn"},
            {"type": "play_sound", "stream": "res://Audio/SFX/hack.res"},
            {"type": "play_sound", "stream": "res://Audio/SFX/neural_beam.res"},
        ],
    }
    var s = SER.skill_from_dict(d)
    _ck(s != null, "скилл с частично битыми эффектами выжил")
    if s == null:
        _fails += 1
        return
    _ck(s.effects.size() == 2, "снаряд с чужим путём отброшен, aoe+звук остались")
    var has_sound := false
    for e in s.effects:
        var bn := str(e.get_script().resource_path.get_file().get_basename())
        if bn == "AoeDamageEffect":
            _ck(e.vfx_scene == null, "vfx вне белого списка -> null (aoe жив)")
        if bn == "PlaySoundEffect":
            has_sound = true
            _ck(e.audio_stream != null, "валидный звук прошёл")
    _ck(has_sound, "валидный play_sound присутствует")


func _test_register_gate() -> void:
    print("-- register-гейт")
    var d := {
        "id": "user_gate", "name": "Гейт", "price": 1,
        "effects": [{"type": "teleport", "vfx": "res://Scenes/teleport_effect.tscn"}],
    }
    var s = SER.skill_from_dict(d)
    _ck(s != null, "минимальный user-скилл разбирается")
    if s == null:
        _fails += 1
        return
    _ck(SDB.register("nope", s) == false, "register без префикса user_ отклонён")
    _ck(not SDB.get_skills().has("nope"), "реестр не изменился")
    _ck(SDB.register("user_gate", s) == true, "register с user_ префиксом принят")
    _ck(SDB.get_skills().has("user_gate"), "скилл в реестре сразу кастуем")
    var d2 := {"id": "user_gate", "name": "Дубль", "effects": [{"type": "teleport", "vfx": ""}]}
    var s2 = SER.skill_from_dict(d2)
    _ck(SDB.register("user_gate", s2) == false, "повторный register того же id отклонён")
    _ck(SDB.get_skills()["user_gate"].skill_name == "Гейт", "конфликт не перетёр существующий")


func _test_persist() -> void:
    print("-- персист JSON")
    var gpath := ProjectSettings.globalize_path(USDB.SAVE_PATH)
    if FileAccess.file_exists(USDB.SAVE_PATH):
        DirAccess.remove_absolute(gpath)
    var d_a := {
        "id": "user_alpha", "name": "Альфа", "icon": "🔮", "price": 2,
        "effects": [{"type": "aoe", "radius": 5.0, "damage": 30,
            "vfx": "res://Scenes/heart_burst.tscn"}],
    }
    _ck(USDB.save_skill(d_a) == true, "save_skill валидного словаря")
    _ck(FileAccess.file_exists(USDB.SAVE_PATH), "файл user://custom_skills.json создан")
    var lst = USDB.list()
    _ck(lst.size() == 1 and str(lst[0].get("id")) == "user_alpha", "list возвращает сохранённое")
    var d_a2 = d_a.duplicate(true)
    d_a2["price"] = 5
    _ck(USDB.save_skill(d_a2) == true, "перезапись под тем же id")
    lst = USDB.list()
    _ck(lst.size() == 1 and int(lst[0].get("price")) == 5, "дубликата нет, значение обновлено")
    var d_fb = d_a.duplicate(true)
    d_fb["id"] = "fireball"
    _ck(USDB.save_skill(d_fb) == false, "save_skill: id без user_ отклонён")
    _ck(USDB.save_skill({"id": "user_noeff", "name": "x"}) == false, "save_skill: битая запись отклонена")
    # load_all: смешанный файл (валидный + подмена встроенного + битый + мусор)
    var mixed := {
        "skills": [
            d_a2,
            {"id": "fireball", "name": "Подмена", "effects": [
                {"type": "aoe", "radius": 3.0, "damage": 5}]},
            {"id": "user_broken"},
            "мусорная строка",
        ],
    }
    var f = FileAccess.open(USDB.SAVE_PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(mixed, "  "))
    f = null
    USDB._loaded = false
    var reg := {}
    var n = USDB.load_all(reg)
    _ck(n == 1, "load_all: загружен 1 из 4 записей")
    _ck(reg.has("user_alpha"), "валидный user-скилл в реестре")
    _ck(not reg.has("fireball"), "id встроенного не перетёрт")
    _ck(reg["user_alpha"].price == 5, "значения из файла корректны")
    # QA#4: повторная загрузка не дублирует (флаг _loaded)
    _ck(USDB.load_all({}) == 0, "повторный load_all — флаг не даёт дубль")
    # Перечитывание файла даёт тот же набор
    USDB._loaded = false
    var reg3 := {}
    USDB.load_all(reg3)
    _ck(reg3.has("user_alpha") and reg3["user_alpha"].skill_name == "Альфа",
        "перечитанный файл даёт тот же скилл")
    # load_all не перетирает существующие ключи реестра
    USDB._loaded = false
    var reg4 := {"user_alpha": "PRE-EXISTING"}
    USDB.load_all(reg4)
    _ck(reg4["user_alpha"] == "PRE-EXISTING", "load_all не перетирает существующие ключи")
    # Битый JSON
    var f2 = FileAccess.open(USDB.SAVE_PATH, FileAccess.WRITE)
    f2.store_string("###НЕ-JSON###")
    f2 = null
    USDB._loaded = false
    var reg5 := {}
    _ck(USDB.load_all(reg5) == 0, "битый JSON: 0 скиллов, без краша")
    _ck(reg5.is_empty(), "реестр не засорён")
    # delete_skill
    _write_valid_file(gpath)
    _ck(USDB.delete_skill("user_alpha") == true, "delete_skill удаляет")
    _ck(USDB.delete_skill("user_alpha") == false, "delete_skill повторно = false")
    # Cleanup — не оставлять тестовые скиллы реальной игре
    DirAccess.remove_absolute(gpath)
    _ck(not FileAccess.file_exists(USDB.SAVE_PATH), "тестовый файл удалён (чисто для игры)")


func _write_valid_file(gpath: String) -> void:
    var f = FileAccess.open(gpath, FileAccess.WRITE)
    f.store_string(JSON.stringify({"skills": [
        {"id": "user_alpha", "name": "Альфа", "price": 1, "effects": [
            {"type": "teleport", "vfx": ""}]},
    ]}, "  "))
    f = null
