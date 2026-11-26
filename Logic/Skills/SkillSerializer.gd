extends RefCounted

## Сериализация Skill <-> Dictionary для Кузницы скиллов (Q36).
## SSOT границ данных: UI-ползунки импортируют константы CLAMP_* —
## границы ползунков == границы данных (правило 10 PRP).
## Пути ассетов — ТОЛЬКО белые списки (произвольные пути из JSON запрещены,
## правило 4 PRP); каждый путь дополнительно проверяется ResourceLoader.exists.
## Битая запись — пропуск + лог, весь файл не валим (правило 3 PRP).

const SKILL_SCRIPT := preload("res://Logic/Skills/Skill.gd")

const EFFECT_SCRIPTS := {
    "spawn_projectile": preload("res://Logic/Skills/SpawnProjectileEffect.gd"),
    "homing_projectile": preload("res://Logic/Skills/SpawnHomingProjectileEffect.gd"),
    "homing_heal": preload("res://Logic/Skills/SpawnHomingHealProjectileEffect.gd"),
    "hitscan": preload("res://Logic/Skills/SpawnHitscanEffect.gd"),
    "aoe": preload("res://Logic/Skills/AoeDamageEffect.gd"),
    "teleport": preload("res://Logic/Skills/TeleportEffect.gd"),
    "play_sound": preload("res://Logic/Skills/PlaySoundEffect.gd"),
}

const TYPE_BY_SCRIPT := {
    "SpawnProjectileEffect": "spawn_projectile",
    "SpawnHomingProjectileEffect": "homing_projectile",
    "SpawnHomingHealProjectileEffect": "homing_heal",
    "SpawnHitscanEffect": "hitscan",
    "AoeDamageEffect": "aoe",
    "TeleportEffect": "teleport",
    "PlaySoundEffect": "play_sound",
}

# Клампы: Vector2i для int-полей, Vector2 для float-полей. UI импортирует их же.
const CLAMP_DAMAGE := Vector2i(1, 150)
const CLAMP_RADIUS := Vector2(2.0, 15.0)
const CLAMP_RANGE := Vector2(2.0, 200.0)
const CLAMP_PRICE := Vector2i(0, 10)
const CLAMP_CAST_TIME := Vector2(0.0, 3.0)
## Окно отмены инста-каста (доля клипа) — стандарт 55–60 %, см. Skill.cancel_at.
const CLAMP_CANCEL_AT := Vector2(0.0, 1.0)
## Темп каст-клипа (Skill.cast_speed): 1.0 = как записан, 2.0 = вдвое быстрее.
## Потолок 4.0 — дальше клип превращается в дёрганье (замер probe_cast_speed).
const CLAMP_CAST_SPEED := Vector2(0.25, 4.0)
const CLAMP_SPAWN_DELAY := Vector2(0.0, 1.0)
const CLAMP_SHAKE := Vector2(0.0, 1.0)
const CLAMP_BEAM_WIDTH := Vector2(0.01, 0.3)
const CLAMP_BEAM_LIFETIME := Vector2(0.03, 0.5)
const CLAMP_OFFSET_Y := Vector2(0.0, 2.0)
const CLAMP_DECAL_SIZE := Vector2(0.1, 3.0)
const CLAMP_DECAL_SCALE := Vector2(0.2, 3.0)
const CLAMP_VOLUME_DB := Vector2(-30.0, 6.0)

# Белые списки ассетов (источник — фактические файлы проекта)
const PROJECTILE_SCENES := [
    "res://Scenes/fireball.tscn",
    "res://Scenes/ball_lightning.tscn",
    "res://Scenes/heart_projectile.tscn",
]
const VFX_SCENES := [
    "res://Scenes/thunder_effect.tscn",
    "res://Scenes/teleport_effect.tscn",
    "res://Scenes/heart_burst.tscn",
]
const SOUNDS := [
    "res://Audio/SFX/neural_fireball.res",
    "res://Audio/SFX/neural_teleport.res",
    "res://Audio/SFX/neural_thunder.res",
    "res://Audio/SFX/neural_meteor_fly.res",
    "res://Audio/SFX/neural_meteor_impact.res",
    "res://Audio/SFX/neural_ball_lightning.res",
    "res://Audio/SFX/neural_beam.res",
    "res://Audio/SFX/neural_heart_heal.res",
]
## Белый список каст-анимаций БОЛЬШЕ НЕ ПРАВИТСЯ РУКАМИ (26.11.26): имена
## выводятся из самой каст-библиотеки (`ual_casts_test.res`), поэтому новый клип,
## добавленный импортёром/бейком, автоматически становится допустимым.
## Это по-прежнему белый список (произвольная строка из JSON не пройдёт), но
## источник — реальные клипы, а не список, который забывали обновлять.
## FALLBACK — если библиотека не загрузилась (урезанная сборка/тест): старое
## поведение, чтобы сохранение скиллов не потеряло ВСЕ анимации разом.
const CAST_LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"
const CAST_ANIMS_FALLBACK := ["", "Throw", "Cast_Shoot", "Heart_Cast", "Throw_L",
    "Cast_Shoot_L", "Heart_Cast_L", "Spell_Cast", "Spell_Cast_L", "Cast_1H_Magic_01"]
static var _cast_names_cache: Array = []
static var _cast_names_loaded := false
const TARGET_TYPES := ["enemy", "ally"]
const CAST_HANDS := ["Right", "Left"]

## Допустимые имена каст-анимаций: базовые клипы библиотеки (без `_UB` —
## суффикс добавляет код, в данных скилла имя всегда базовое).
## Источник — реальная библиотека, см. CAST_LIB_PATH. Кэш: библиотека не
## меняется в рантайме (пересобирается только генераторами при разработке).
static func cast_anims() -> Array:
    if not _cast_names_loaded:
        _cast_names_loaded = true
        var names: Array = [""]
        var lib = load(CAST_LIB_PATH) if ResourceLoader.exists(CAST_LIB_PATH) else null
        if lib is AnimationLibrary:
            var all: Array = lib.get_animation_list()
            all.sort()
            for n in all:
                var s := String(n)
                if s.ends_with("_UB"):
                    continue   # служебный суффикс бейка, в данных не используется
                names.append(s)
        else:
            _warn("каст-библиотека не загрузилась (%s) — список анимаций из FALLBACK" % CAST_LIB_PATH)
            names = CAST_ANIMS_FALLBACK.duplicate()
        _cast_names_cache = names
    return _cast_names_cache

## Обратная совместимость: старый код/тесты обращались к CAST_ANIMS как к
## константе-массиву. Теперь это функция-источник; хелпер проверки — has_cast_anim.
static func has_cast_anim(name: String) -> bool:
    return cast_anims().has(name)

const NAME_MAX := 32
const DESC_MAX := 200
const ICON_MAX := 8


static func skill_to_dict(s) -> Dictionary:
    ## Skill -> словарь JSON-схемы Кузницы (schema в PRP Шаг 1).
    ## Эффекты вне MVP-набора (SpawnWings/Blade/Portals/SoftAim) пропускаются.
    var d := {
        "id": str(s.id),
        "name": str(s.skill_name).substr(0, NAME_MAX),
        "description": str(s.description).substr(0, DESC_MAX),
        "icon": str(s.icon).substr(0, ICON_MAX),
        "price": clampi(int(s.price), CLAMP_PRICE.x, CLAMP_PRICE.y),
        "max_range": clampf(float(s.max_range), CLAMP_RANGE.x, CLAMP_RANGE.y),
        "requires_target": bool(s.requires_target),
        "target_type": s.target_type if TARGET_TYPES.has(s.target_type) else "enemy",
        "cast_anim": s.cast_anim if has_cast_anim(s.cast_anim) else "",
        # Очередь клипов того же скилла (26.11.26, энергоклинок A→B): второй
        # клип круга. Валидируется тем же белым списком, что и cast_anim.
        "next_cast_anim": s.next_cast_anim if has_cast_anim(s.next_cast_anim) else "",
        # Клип-состояние (крылья): loop-поза вместо разового удара.
        "cast_anim_loop": bool(s.cast_anim_loop),
        # Поза стойки (26.11.26, бард: гитара). Отдельное поле, а не cast_anim:
        # у стойки нет каст-удара. Админка показывает её как «клип в игре» —
        # без этого стойки выглядели как «анимация не задана» (ложная тревога).
        "stance_loop_anim": s.stance_loop_anim if has_cast_anim(s.stance_loop_anim) else "",
        "cast_time": clampf(float(s.cast_time), CLAMP_CAST_TIME.x, CLAMP_CAST_TIME.y),
        "cast_hand": s.cast_hand if CAST_HANDS.has(s.cast_hand) else "Right",
        "cast_speed": clampf(float(s.cast_speed), CLAMP_CAST_SPEED.x, CLAMP_CAST_SPEED.y),
        "alternate_hands": bool(s.alternate_hands),
        "cancel_at": clampf(float(s.cancel_at), CLAMP_CANCEL_AT.x, CLAMP_CANCEL_AT.y),
        "shake": clampf(float(s.shake), CLAMP_SHAKE.x, CLAMP_SHAKE.y),
        "effects": [],
    }
    for e in s.effects:
        var ed := _effect_to_dict(e)
        if not ed.is_empty():
            d["effects"].append(ed)
    return d


static func skill_from_dict(d: Dictionary):
    ## Словарь -> Skill (клампы + белые списки). null = запись битая (лог в Logger).
    var s = SKILL_SCRIPT.new()
    s.id = str(d.get("id", ""))
    if s.id.is_empty():
        _warn("запись без id — пропущена")
        return null
    s.skill_name = str(d.get("name", "Без имени")).substr(0, NAME_MAX)
    s.description = str(d.get("description", "")).substr(0, DESC_MAX)
    s.icon = str(d.get("icon", "✨")).substr(0, ICON_MAX)
    s.price = clampi(int(d.get("price", 1)), CLAMP_PRICE.x, CLAMP_PRICE.y)
    s.max_range = clampf(float(d.get("max_range", 200.0)), CLAMP_RANGE.x, CLAMP_RANGE.y)
    s.requires_target = bool(d.get("requires_target", false))
    var tt := str(d.get("target_type", "enemy"))
    s.target_type = tt if TARGET_TYPES.has(tt) else "enemy"
    var ca := str(d.get("cast_anim", ""))
    s.cast_anim = ca if has_cast_anim(ca) else ""
    var nca := str(d.get("next_cast_anim", ""))
    s.next_cast_anim = nca if has_cast_anim(nca) else ""
    s.cast_anim_loop = bool(d.get("cast_anim_loop", false))
    var sla := str(d.get("stance_loop_anim", ""))
    s.stance_loop_anim = sla if has_cast_anim(sla) else ""
    var ch := str(d.get("cast_hand", "Right"))
    s.cast_hand = ch if CAST_HANDS.has(ch) else "Right"
    s.cast_speed = clampf(float(d.get("cast_speed", 1.0)), CLAMP_CAST_SPEED.x, CLAMP_CAST_SPEED.y)
    s.cast_time = clampf(float(d.get("cast_time", 0.0)), CLAMP_CAST_TIME.x, CLAMP_CAST_TIME.y)
    s.alternate_hands = bool(d.get("alternate_hands", false))
    s.cancel_at = clampf(float(d.get("cancel_at", 0.6)), CLAMP_CANCEL_AT.x, CLAMP_CANCEL_AT.y)
    s.shake = clampf(float(d.get("shake", 0.0)), CLAMP_SHAKE.x, CLAMP_SHAKE.y)
    var arr = d.get("effects", null)
    if not (arr is Array):
        _warn("запись %s: effects не массив — пропущена" % s.id)
        return null
    for ed in arr:
        if ed is Dictionary:
            var e = _effect_from_dict(ed)
            if e != null:
                s.effects.append(e)
    if s.effects.is_empty():
        _warn("запись %s: ни одного валидного эффекта — пропущена" % s.id)
        return null
    return s


static func _effect_from_dict(ed: Dictionary):
    ## Один эффект из словаря. null = эффект отброшен (снаряд/звук без ресурса,
    ## неизвестный тип). aoe/teleport живут и без vfx (гарды null есть в эффектах).
    var t := str(ed.get("type", ""))
    if not EFFECT_SCRIPTS.has(t):
        _warn("неизвестный тип эффекта '%s' — эффект пропущен" % t)
        return null
    var e = EFFECT_SCRIPTS[t].new()
    match t:
        "spawn_projectile":
            e.projectile_scene = _res(ed.get("scene", ""), PROJECTILE_SCENES, "сцена снаряда")
            if e.projectile_scene == null:
                return null  # снаряд без сцены бесполезен
            e.spawn_from_hand = bool(ed.get("spawn_from_hand", false))
            e.spawn_delay = _cf(ed.get("spawn_delay", 0.0), CLAMP_SPAWN_DELAY)
            e.offset_y = _cf(ed.get("offset_y", 1.2), CLAMP_OFFSET_Y)
            e.impact_shake = _cf(ed.get("impact_shake", 0.0), CLAMP_SHAKE)
            e.impact_sound = _res(ed.get("impact_sound", ""), SOUNDS, "звук")
            e.decal_scale = _cf(ed.get("decal_scale", 1.0), CLAMP_DECAL_SCALE)
            e.lava_pool = bool(ed.get("lava_pool", false))
        "homing_projectile", "homing_heal":
            e.projectile_scene = _res(ed.get("scene", ""), PROJECTILE_SCENES, "сцена снаряда")
            if e.projectile_scene == null:
                return null
            e.spawn_from_hand = bool(ed.get("spawn_from_hand", false))
            e.spawn_delay = _cf(ed.get("spawn_delay", 0.0), CLAMP_SPAWN_DELAY)
            e.offset_y = _cf(ed.get("offset_y", 1.2), CLAMP_OFFSET_Y)
        "hitscan":
            e.damage = _ci(ed.get("damage", 30), CLAMP_DAMAGE)
            e.beam_width = _cf(ed.get("beam_width", 0.06), CLAMP_BEAM_WIDTH)
            e.beam_lifetime = _cf(ed.get("beam_lifetime", 0.12), CLAMP_BEAM_LIFETIME)
            e.offset_y = _cf(ed.get("offset_y", 1.2), CLAMP_OFFSET_Y)
            e.leave_decal = bool(ed.get("leave_decal", true))
            e.decal_size = _cf(ed.get("decal_size", 0.7), CLAMP_DECAL_SIZE)
            e.spawn_from_hand = bool(ed.get("spawn_from_hand", false))
            e.spawn_delay = _cf(ed.get("spawn_delay", 0.0), CLAMP_SPAWN_DELAY)
            var cstr := str(ed.get("beam_color", ""))
            if cstr.length() >= 6:
                e.beam_color = Color.html(cstr)
        "aoe":
            e.radius = _cf(ed.get("radius", 5.0), CLAMP_RADIUS)
            e.damage = _ci(ed.get("damage", 30), CLAMP_DAMAGE)
            e.vfx_scene = _res(ed.get("vfx", ""), VFX_SCENES, "vfx")
        "teleport":
            e.vfx_scene = _res(ed.get("vfx", ""), VFX_SCENES, "vfx")
        "play_sound":
            e.audio_stream = _res(ed.get("stream", ""), SOUNDS, "звук")
            if e.audio_stream == null:
                return null  # звуковой эффект без звука бесполезен
            var streams = ed.get("streams", [])
            if streams is Array:
                for p in streams:
                    var r = _res(str(p), SOUNDS, "звук")
                    if r != null:
                        e.audio_streams.append(r)
            e.volume_db = _cf(ed.get("volume_db", 0.0), CLAMP_VOLUME_DB)
    return e


static func _effect_to_dict(e) -> Dictionary:
    var sname := str(e.get_script().resource_path.get_file().get_basename())
    var t: String = TYPE_BY_SCRIPT.get(sname, "")
    if t.is_empty():
        _warn("эффект %s вне MVP-набора — не сериализован" % sname)
        return {}
    match t:
        "spawn_projectile":
            return {
                "type": t,
                "scene": _path_of(e.projectile_scene),
                "spawn_from_hand": bool(e.spawn_from_hand),
                "spawn_delay": float(e.spawn_delay),
                "offset_y": float(e.offset_y),
                "impact_shake": float(e.impact_shake),
                "impact_sound": _path_of(e.impact_sound),
                "decal_scale": float(e.decal_scale),
                "lava_pool": bool(e.lava_pool),
            }
        "homing_projectile", "homing_heal":
            return {
                "type": t,
                "scene": _path_of(e.projectile_scene),
                "spawn_from_hand": bool(e.spawn_from_hand),
                "spawn_delay": float(e.spawn_delay),
                "offset_y": float(e.offset_y),
            }
        "hitscan":
            return {
                "type": t,
                "damage": int(e.damage),
                "beam_color": e.beam_color.to_html(true),
                "beam_width": float(e.beam_width),
                "beam_lifetime": float(e.beam_lifetime),
                "offset_y": float(e.offset_y),
                "leave_decal": bool(e.leave_decal),
                "decal_size": float(e.decal_size),
                "spawn_from_hand": bool(e.spawn_from_hand),
                "spawn_delay": float(e.spawn_delay),
            }
        "aoe":
            return {
                "type": t,
                "radius": float(e.radius),
                "damage": int(e.damage),
                "vfx": _path_of(e.vfx_scene),
            }
        "teleport":
            return {"type": t, "vfx": _path_of(e.vfx_scene)}
        "play_sound":
            var streams: Array = []
            for st in e.audio_streams:
                streams.append(_path_of(st))
            return {
                "type": t,
                "stream": _path_of(e.audio_stream),
                "streams": streams,
                "volume_db": float(e.volume_db),
            }
    return {}


static func _res(path: String, whitelist: Array, what: String):
    ## Путь -> Resource: белое списке + exists, иначе null (лог).
    if path == "":
        return null
    if not whitelist.has(path):
        _warn("путь вне белого списка (%s): %s" % [what, path])
        return null
    if not ResourceLoader.exists(path):
        _warn("ресурс отсутствует (%s): %s" % [what, path])
        return null
    return load(path)


static func _path_of(res) -> String:
    if res == null:
        return ""
    return str(res.resource_path)


static func _cf(v, cl: Vector2) -> float:
    return clampf(float(v), cl.x, cl.y)


static func _ci(v, cl: Vector2i) -> int:
    return clampi(int(v), cl.x, cl.y)


static func _warn(msg: String) -> void:
    ## Консоль + лог в Logger-автолоад. Из статики имя автолоада резолвится
    ## в КЛАСС скрипта, а не в инстанс — инстанс берём через дерево сцен.
    print("SkillSerializer: %s" % msg)
    _logger_write("SkillSerializer: %s" % msg)


static func _logger_write(line: String) -> void:
    var ml := Engine.get_main_loop()
    if ml is SceneTree:
        var lg = (ml as SceneTree).root.get_node_or_null("/root/Logger")
        if lg != null:
            lg.log_message(line)
