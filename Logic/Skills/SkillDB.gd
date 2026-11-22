extends RefCounted

static var _skills: Dictionary = {}
static var _initialized: bool = false

# Кузница скиллов (Q36): персист пользовательских скиллов (user://custom_skills.json).
const UserSkillDBScript := preload("res://Logic/Skills/UserSkillDB.gd")

static func register(id: String, skill: Resource) -> bool:
    # Единственная легальная точка входа пользовательских скиллов в реестр.
    # Префикс user_ обязателен; конфликт id — отказ, встроенные не перетираются.
    if skill == null:
        _log("register: skill null — отклонён (%s)" % id)
        return false
    if not id.begins_with("user_"):
        _log("register: id без префикса user_ отклонён: %s" % id)
        return false
    if _skills.has(id):
        _log("register: конфликт id, встроенный не перетирается: %s" % id)
        return false
    _skills[id] = skill
    _log("register: зарегистрирован %s" % id)
    return true


static func replace(id: String, skill: Resource) -> bool:
    # Перезапись ПОЛЬЗОВАТЕЛЬСКОГО скилла (правка из Кузницы, Q36):
    # префикс user_ обязателен, встроенные не трогаются.
    if skill == null:
        _log("replace: skill null — отклонён (%s)" % id)
        return false
    if not id.begins_with("user_"):
        _log("replace: id без префикса user_ отклонён: %s" % id)
        return false
    if not _skills.has(id):
        _log("replace: скилла нет в реестре — используй register (%s)" % id)
        return false
    _skills[id] = skill
    _log("replace: перезаписан %s" % id)
    return true


static func unregister(id: String) -> bool:
    # Удаление пользовательского скилла из реестра (Кузница Q36).
    if not id.begins_with("user_"):
        _log("unregister: id без префикса user_ отклонён: %s" % id)
        return false
    if not _skills.has(id):
        return false
    _skills.erase(id)
    _log("unregister: удалён %s" % id)
    return true


static func _log(msg: String) -> void:
    # Консоль + лог в Logger-автолоад (из статики автолоад-имя резолвится
    # в КЛАСС скрипта, а не в инстанс — инстанс берём через дерево сцен).
    print("SkillDB: %s" % msg)
    var ml := Engine.get_main_loop()
    if ml is SceneTree:
        var lg = (ml as SceneTree).root.get_node_or_null("/root/Logger")
        if lg != null:
            lg.log_message("SkillDB: %s" % msg)

static func get_skills() -> Dictionary:
    if _initialized:
        return _skills
        
    _initialized = true
    
    var fb = preload("res://Logic/Skills/Skill.gd").new()
    fb.id = "fireball"
    fb.skill_name = "Огненный Шар"
    fb.description = "Базовый снаряд.\nСкорость: 20 м/с."
    fb.icon = "🔥"
    fb.price = 1
    fb.max_range = 200.0
    var proj = preload("res://Logic/Skills/SpawnProjectileEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/fireball.tscn"):
        proj.projectile_scene = load("res://Scenes/fireball.tscn")
    proj.spawn_from_hand = true  # инста-каст из правой кисти (план 17.11.26)
    # Спавн в момент ТОЛЧКА единого каст-жеста (cast_push: пик z0.82@k12≈0.4 с;
    # вердикт 17.11.26: снаряд не должен улетать раньше жеста).
    proj.spawn_delay = 0.35
    fb.effects.append(proj)
    # Инста-каст-анимация: единый каст-жест (cast_push, толчок вперёд на
    # высоте груди — вердикт 17.11.26: «волейбольный замах — это не каст»).
    fb.cast_anim = "Throw"
    # Нейро-звук (Шаг 5.1 A/B): MOSS v2, 48 кГц — Audio/Gen/neural/fireball.wav.
    var fb_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    fb_sound.audio_stream = load("res://Audio/SFX/neural_fireball.res")
    fb_sound.volume_db = 0.0  # громкость выровнена RMS-нормализацией клипов
    fb.effects.append(fb_sound)
    _skills["fireball"] = fb

    var tp = preload("res://Logic/Skills/Skill.gd").new()
    tp.id = "teleport"
    tp.skill_name = "Телепорт (20м)"
    tp.description = "Стремительный рывок на 20 м."
    tp.icon = "🌌"
    tp.price = 2
    tp.max_range = 20.0
    var tel = preload("res://Logic/Skills/TeleportEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/teleport_effect.tscn"):
        tel.vfx_scene = load("res://Scenes/teleport_effect.tscn")
    tp.effects.append(tel)
    # Нейро-звук (Шаг 5.1 A/B): MOSS v2 — Audio/Gen/neural/teleport_warp.wav.
    var tp_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    tp_sound.audio_stream = load("res://Audio/SFX/neural_teleport.res")
    tp_sound.volume_db = 0.0  # громкость выровнена RMS-нормализацией клипов
    tp.effects.append(tp_sound)
    _skills["teleport"] = tp

    var dj = preload("res://Logic/Skills/Skill.gd").new()
    dj.id = "double_jump"
    dj.skill_name = "Двойной прыжок"
    dj.description = "Позволяет прыгать в воздухе."
    dj.icon = "🏃"
    dj.price = 1
    dj.is_passive = true
    _skills["double_jump"] = dj
    
    var thunder = preload("res://Logic/Skills/Skill.gd").new()
    thunder.id = "thunderclap"
    thunder.skill_name = "Громовой раскат"
    thunder.description = "Взрыв по площади (AoE)."
    thunder.icon = "⚡"
    thunder.price = 3
    thunder.max_range = 30.0
    var aoe = preload("res://Logic/Skills/AoeDamageEffect.gd").new()
    aoe.radius = 6.0
    aoe.damage = 40
    if ResourceLoader.exists("res://Scenes/thunder_effect.tscn"):
        aoe.vfx_scene = load("res://Scenes/thunder_effect.tscn")
    thunder.effects.append(aoe)
    # Нейро-звук (Шаг 5.1 A/B): MOSS v2 — Audio/Gen/neural/thunderclap.wav.
    var th_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    th_sound.audio_stream = load("res://Audio/SFX/neural_thunder.res")
    th_sound.volume_db = 0.0  # громкость выровнена K-нормализацией клипов
    thunder.effects.append(th_sound)
    # Длительный каст двумя руками (вердикт 17.11.26): канал 1 с.
    thunder.cast_time = 1.0
    # Тряска камеры на взрыве (верб. юзера 19.11.26: «экран слегка трясло»).
    thunder.shake = 0.4
    _skills["thunderclap"] = thunder
    
    var meteor = preload("res://Logic/Skills/Skill.gd").new()
    meteor.id = "meteor"
    meteor.skill_name = "Огненный Метеорит"
    meteor.description = "Мощный снаряд и AoE урон."
    meteor.icon = "☄️"
    meteor.price = 5
    meteor.max_range = 60.0
    var m_proj = preload("res://Logic/Skills/SpawnProjectileEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/fireball.tscn"):
        m_proj.projectile_scene = load("res://Scenes/fireball.tscn")
    m_proj.offset_y = 15.0  # метеор летит С НЕБА (не из руки) — канал 2 с
    # Тряска камеры при ПАДЕНИИ метеорита (верб. юзера 19.11.26) — момент
    # удара, не каста: impact_shake играет ProjectileComponent при попадании.
    m_proj.impact_shake = 0.6
    # Звук УДАРА о землю (17.11.26 вердикт: метеор = свист полёта + взрыв
    # удара). SpawnProjectileEffect кладёт его в meta снаряда; играет
    # ProjectileComponent в точке попадания.
    if ResourceLoader.exists("res://Audio/SFX/neural_meteor_impact.res"):
        m_proj.impact_sound = load("res://Audio/SFX/neural_meteor_impact.res")
    # След на земле (QUEUE Q5, заказ юзера): крупная подпалина + лужа лавы,
    # которую видно долго («лужи лавы, оставляющие след»).
    m_proj.decal_scale = 2.4
    m_proj.lava_pool = true
    meteor.effects.append(m_proj)
    var m_aoe = preload("res://Logic/Skills/AoeDamageEffect.gd").new()
    m_aoe.radius = 8.0
    m_aoe.damage = 60
    if ResourceLoader.exists("res://Scenes/thunder_effect.tscn"):
        m_aoe.vfx_scene = load("res://Scenes/thunder_effect.tscn")
    meteor.effects.append(m_aoe)
    # Звук ПОЛЁТА на касте (17.11.26 вердикт: «покруче и подольше»): нейро-свист
    # падения — Audio/Gen/neural/neural_meteor_fly.wav (4 сек).
    var m_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    m_sound.audio_stream = load("res://Audio/SFX/neural_meteor_fly.res")
    m_sound.volume_db = 0.0  # громкость выровнена K-нормализацией (LUFS)
    meteor.effects.append(m_sound)
    # Длительный каст двумя руками (вердикт 17.11.26): канал 2 с.
    meteor.cast_time = 2.0
    _skills["meteor"] = meteor

    var ball_lightning = preload("res://Logic/Skills/Skill.gd").new()
    ball_lightning.id = "ball_lightning"
    ball_lightning.skill_name = "Шаровая Молния"
    ball_lightning.description = "Самонаводящийся снаряд.\nТребует врага в прицеле.\nСкорость: 6 м/с."
    ball_lightning.icon = "🔮"
    ball_lightning.price = 4
    ball_lightning.max_range = 100.0
    ball_lightning.requires_target = true
    ball_lightning.target_type = "enemy"
    var bl_proj = preload("res://Logic/Skills/SpawnHomingProjectileEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/ball_lightning.tscn"):
        bl_proj.projectile_scene = load("res://Scenes/ball_lightning.tscn")
    bl_proj.spawn_from_hand = true  # инста-каст из правой кисти (план 17.11.26)
    # Cast_Shoot: обе руки вытягиваются к k8≈0.27 с — спавн в момент выброса.
    bl_proj.spawn_delay = 0.3
    ball_lightning.effects.append(bl_proj)
    # Инста-каст: резкий выброс рукой (UAL Pistol_Shoot, ретаргет).
    ball_lightning.cast_anim = "Cast_Shoot"
    ball_lightning.cast_hand = "Left"  # снаряд из анимированной (левой) кисти
    # Нейро-звук v2 (17.11.26 вердикт: тесла-треск с вибрациями) —
    # Audio/Gen/neural/neural_ball_lightning.wav.
    var bl_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    bl_sound.audio_stream = load("res://Audio/SFX/neural_ball_lightning.res")
    bl_sound.volume_db = 0.0  # громкость выровнена K-нормализацией (LUFS)
    ball_lightning.effects.append(bl_sound)
    _skills["ball_lightning"] = ball_lightning

    var heart = preload("res://Logic/Skills/Skill.gd").new()
    heart.id = "heart_heal"
    heart.skill_name = "Сердечко"
    heart.description = "Самонаводящееся лечение (5%).\nТребует союзника.\nСкорость: 10 м/с."
    heart.icon = "💖"
    heart.price = 2
    heart.max_range = 100.0
    heart.requires_target = true
    heart.target_type = "friendly"
    var h_proj = preload("res://Logic/Skills/SpawnHomingHealProjectileEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/heart_projectile.tscn"):
        h_proj.projectile_scene = load("res://Scenes/heart_projectile.tscn")
    h_proj.spawn_from_hand = true  # сердце вылетает из кисти
    # Спавн в момент «отпуска» жеста: конец Enter-подъёма, старт Exit-спада
    # склейки Heart_Cast (0.533 с) → 0.55 с.
    h_proj.spawn_delay = 0.55
    heart.effects.append(h_proj)

    var h_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    # ВЕРДИКТ 17.11.26 (раунд 3): v3a_дзынь — лидер → пул РАНДОМНОЙ РОТАЦИИ
    # (v3a + родственные v3d/v3e/v3f, та же семья «фейри-дзынь», разные сиды).
    # Каждый каст играет случайный вариант пула. Оригинал ogg и v2 — на диске.
    h_sound.audio_streams = [
        load("res://Audio/SFX/heart_heal_v3a.res"),
        load("res://Audio/SFX/heart_heal_v3d.res"),
        load("res://Audio/SFX/heart_heal_v3e.res"),
        load("res://Audio/SFX/heart_heal_v3f.res"),
    ]
    h_sound.volume_db = 0.0  # громкость выровнена K-нормализацией (LUFS)
    heart.effects.append(h_sound)
    # Вердикт 17.11.26: каст = Spell_Simple_Enter + Spell_Simple_Exit (UAL),
    # склеенные в Heart_Cast (левая рука); Heart_Cast_L — иерархическое зеркало
    # (Generators/build_heart_cast.gd). Спам = поочерёдно лево/право.
    heart.cast_anim = "Heart_Cast"
    heart.alternate_hands = true
    _skills["heart_heal"] = heart

    var beam = preload("res://Logic/Skills/Skill.gd").new()
    beam.id = "beam"
    beam.skill_name = "Луч"
    beam.description = "Мгновенный выстрел.\nУрон сразу в точке прицела."
    beam.icon = "🔦"
    beam.price = 3
    beam.max_range = 100.0
    var hitscan = preload("res://Logic/Skills/SpawnHitscanEffect.gd").new()
    hitscan.damage = 35
    # Вердикт 17.11.26 №2 («груз толкает»): Push_Loop не подошёл — луч бьёт
    # резким выбросом ЛЕВОЙ ладони (Cast_Shoot = Spell_Simple_Shoot); cast_hand
    # = Left, чтобы луч шёл из анимированной кисти.
    beam.cast_anim = "Cast_Shoot"
    beam.cast_hand = "Left"
    hitscan.spawn_from_hand = true
    hitscan.spawn_delay = 0.3  # выброс Cast_Shoot ≈0.27 с
    beam.effects.append(hitscan)
    # Нейро-звук (17.11.26 вердикт: нейро лучше, старый лазер удалён).
    var beam_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    beam_sound.audio_stream = load("res://Audio/SFX/neural_beam.res")
    beam_sound.volume_db = 0.0  # громкость выровнена K-нормализацией (LUFS)
    beam.effects.append(beam_sound)
    _skills["beam"] = beam

    # Энергетический клинок (Q19, план спец-батча, одобрен юзером 19.11.26:
    # «Материализация / Энергетический клинок, как в Elden Ring / Devil May Cry»).
    # Одно действие: нет клинка — материализация, есть — взмах (урон).
    var bl = preload("res://Logic/Skills/Skill.gd").new()
    bl.id = "energy_blade"
    bl.skill_name = "Энергетический клинок"
    bl.description = "Материализация клинка в руке (8 с).
Повторный каст — взмах, 35 урона."
    bl.icon = "🗡"
    bl.price = 2
    bl.max_range = 200.0
    # Анимации играет SpawnBladeEffect (режимы требуют разных жестов).
    bl.cast_anim = ""
    bl.effects.append(preload("res://Logic/Skills/SpawnBladeEffect.gd").new())
    _skills["energy_blade"] = bl

    # Крылья ускорения (Q20, спец-батч 19.11.26): светящиеся крылья на 10 с,
    # пока активны — скорость x1.35 (fov + линии скорости как спринт Minecraft).
    # Жест Cast_Enter играет SpawnWingsEffect: IK-доводка руки крыльям не нужна.
    var wg = preload("res://Logic/Skills/Skill.gd").new()
    wg.id = "wings"
    wg.skill_name = "Крылья ускорения"
    wg.description = "Светящиеся крылья на 10 с.
Пока раскрыты — скорость +35% и рывок обзора."
    wg.icon = "🕊"  # U+1FABD 🪽 не рендерился в Win10 (белый квадрат) — фикс Q16 Шаг 9
    wg.price = 2
    wg.max_range = 200.0
    wg.cast_anim = ""
    wg.effects.append(preload("res://Logic/Skills/SpawnWingsEffect.gd").new())
    _skills["wings"] = wg

    # Порталы (Q21, юзер 19.11.26): первый — всегда рядом с персонажем,
    # второй — точка прицела; двусторонний туннель-проход между ними.
    var ptl = preload("res://Logic/Skills/Skill.gd").new()
    ptl.id = "portals"
    ptl.skill_name = "Порталы"
    ptl.description = "Портал у ног и портал в точке прицела.
Зашёл в один — вышел из другого."
    ptl.icon = "🌀"
    ptl.price = 2
    ptl.max_range = 40.0
    ptl.cast_anim = ""
    ptl.effects.append(preload("res://Logic/Skills/SpawnPortalsEffect.gd").new())
    var pts = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    pts.audio_stream = load("res://Audio/SFX/neural_teleport.res")
    pts.volume_db = 0.0
    ptl.effects.append(pts)
    _skills["portals"] = ptl

    # Порталы v2 «живое окно» (Q44, юзер 20.11.26 «да гоу делай»): ОТДЕЛЬНЫЙ
    # скилл, v1 «portals» остаётся старой версией. Окно в другой конец пары,
    # проскок через мембрану (не телепорт-сдвиг), снаряды/лучи проходят,
    # пара живёт 30 с. ССОТ плана — tasks/portals_v2_prp.md.
    var ptl2 = preload("res://Logic/Skills/Skill.gd").new()
    ptl2.id = "portals2"
    ptl2.skill_name = "Порталы v2"
    ptl2.description = "Живое окно в другой конец: сквозь мембрану видно
другую локацию, снаряды и лучи проходят внутрь. Заходишь в один —
выходишь из другого плавным проскоком. Пара живёт 30 секунд."
    ptl2.icon = "🌀"
    ptl2.price = 4
    ptl2.max_range = 40.0
    ptl2.cast_anim = ""
    ptl2.effects.append(preload("res://Logic/Skills/SpawnPortals2Effect.gd").new())
    var pts2 = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    pts2.audio_stream = load("res://Audio/SFX/neural_teleport.res")
    pts2.volume_db = 0.0
    ptl2.effects.append(pts2)
    _skills["portals2"] = ptl2

    # ---------- Стойка «Концентрация маны» (Q16 Шаг 2, ТЗ спеца) ----------
    # Под-приёмы — НЕ в магазине (is_sub_skill=true, Шаг 0): выдаются только
    # вместе со стойкой-родителем. Базовые регистрируются НАПРЯМУЮ в _skills:
    # гварды register/replace требуют user_ (Кузница).
    var mcrush = preload("res://Logic/Skills/Skill.gd").new()
    mcrush.id = "mana_crush"
    mcrush.skill_name = "Сокрушение маны"
    mcrush.description = "Мили-удар перед собой: урон и отброс."
    mcrush.icon = "🤜"
    mcrush.is_sub_skill = true
    mcrush.max_range = 6.0
    mcrush.effects.append(preload("res://Logic/Skills/MeleeShoveEffect.gd").new())
    _skills["mana_crush"] = mcrush

    var mbolt = preload("res://Logic/Skills/Skill.gd").new()
    mbolt.id = "mana_bolt"
    mbolt.skill_name = "Сгусток маны"
    mbolt.description = "Снаряд по прицелу (урон множится зарядом стойки)."
    mbolt.icon = "🔹"
    mbolt.is_sub_skill = true
    mbolt.max_range = 100.0
    var mb_proj = preload("res://Logic/Skills/SpawnProjectileEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/mana_bolt.tscn"):
        mb_proj.projectile_scene = load("res://Scenes/mana_bolt.tscn")
    mb_proj.spawn_from_hand = true
    mbolt.effects.append(mb_proj)
    _skills["mana_bolt"] = mbolt

    var mcres = preload("res://Logic/Skills/Skill.gd").new()
    mcres.id = "mana_crescent"
    mcres.skill_name = "Серп маны"
    mcres.description = "Широкий разрез: все враги в секторе ±60° перед тобой."
    mcres.icon = "🌙"
    mcres.is_sub_skill = true
    mcres.max_range = 14.0
    mcres.effects.append(preload("res://Logic/Skills/CrescentWaveEffect.gd").new())
    _skills["mana_crescent"] = mcres

    # Стойка-родитель (Q-скилл): вход в стойку + звук входа (reuse нейро-молния).
    var mconc = preload("res://Logic/Skills/Skill.gd").new()
    mconc.id = "mana_concentration"
    mconc.skill_name = "Концентрация маны"
    mconc.description = "Стойка 4 с: ЛКМ/ПКМ/Q подменяются приёмами.
Заряд (до 1.5 с) усиливает приёмы: x1.0 → x1.3 → x1.6.
Esc — отмена."
    mconc.icon = "✨"
    mconc.price = 4
    mconc.max_range = 200.0
    var m_ent = preload("res://Logic/Skills/EnterStanceEffect.gd").new()
    m_ent.stance_id = "mana_concentration"
    m_ent.duration = 4.0
    mconc.effects.append(m_ent)
    var mc_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    mc_sound.audio_stream = load("res://Audio/SFX/neural_ball_lightning.res")
    mc_sound.volume_db = 0.0
    mconc.effects.append(mc_sound)
    var m_subs: Array[Dictionary] = [
        {"id": "mana_crush", "label": "Сокрушение", "default_slot": "ЛКМ"},
        {"id": "mana_bolt", "label": "Сгусток", "default_slot": "ПКМ"},
        {"id": "mana_crescent", "label": "Серп", "default_slot": "self"},
    ]
    mconc.stance_sub_skills = m_subs
    mconc.stance_exit_on_sub = true  # вердикт юзера 22.11.26: приём = разряд стойки
    _skills["mana_concentration"] = mconc

    # Стойка «Поток Гармонии» (Q16 Шаг 6, R-скилл): ритм-куполов-стойка барда.
    var bflow = preload("res://Logic/Skills/Skill.gd").new()
    bflow.id = "bard_flow"
    bflow.skill_name = "Поток Гармонии"
    bflow.description = "Стойка-концерт: ЛКМ/ПКМ подменяются ритм-нотами.
Топливо 5 с: Perfect +1.2 / Good +0.5 / Miss −0.5, потолок 14 с.
Купол поглощает урон (15→50% по tier), рикошет 15→60%. Esc/Бас-Дроп — выход."
    bflow.icon = "🎵"  # U+1FABD 🪽 не рендерился в Win10 (белый квадрат) — фикс Q16 Шаг 9
    bflow.price = 5
    bflow.max_range = 200.0
    var b_ent = preload("res://Logic/Skills/EnterStanceEffect.gd").new()
    b_ent.stance_id = "bard_flow"
    # Топливо живёт в BardFlowComponent (99 с — только страховка; выход по
    # fuel_out / barrier_break / bard_drop / max_duration / Esc).
    b_ent.duration = 99.0
    bflow.effects.append(b_ent)
    var b_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    b_sound.audio_stream = load("res://Audio/Bard/note_a4.res")
    b_sound.volume_db = 0.0
    bflow.effects.append(b_sound)
    var b_subs: Array[Dictionary] = [
        {"id": "bard_note", "label": "Ноты Гармонии", "default_slot": "ЛКМ"},
        {"id": "bard_chord", "label": "Ударный Аккорд", "default_slot": "ПКМ"},
        {"id": "bard_drop", "label": "Бас-Дроп", "default_slot": "self"},
    ]
    bflow.stance_sub_skills = b_subs
    _skills["bard_flow"] = bflow

    # Под-приёмы Потока (Q16 Шаг 6).
    var bnote = preload("res://Logic/Skills/Skill.gd").new()
    bnote.id = "bard_note"
    bnote.skill_name = "Ноты Гармонии"
    bnote.description = "Каждое нажатие — консонансная нота пентатоники.
Ритм-сетка: восьмые доли. Perfect +1.2 с топлива, Miss −1.5 с."
    bnote.icon = "🎼"
    bnote.is_sub_skill = true
    bnote.max_range = 200.0
    bnote.effects.append(preload("res://Logic/Skills/BardNoteEffect.gd").new())
    _skills["bard_note"] = bnote

    var bchord = preload("res://Logic/Skills/Skill.gd").new()
    bchord.id = "bard_chord"
    bchord.skill_name = "Ударный Аккорд"
    bchord.description = "Звуковая волна урона по прицелу (сильные доли).
Урон × tier-множитель Потока (1.0→1.3)."
    bchord.icon = "🔊"
    bchord.is_sub_skill = true
    bchord.max_range = 14.0
    var bc_aoe = preload("res://Logic/Skills/AoeDamageEffect.gd").new()
    bc_aoe.radius = 5.0
    bc_aoe.damage = 30
    bc_aoe.center_on_caster = false
    bchord.effects.append(bc_aoe)
    _skills["bard_chord"] = bchord

    var bdrop = preload("res://Logic/Skills/Skill.gd").new()
    bdrop.id = "bard_drop"
    bdrop.skill_name = "Финальный Бас-Дроп"
    bdrop.description = "Финал Потока: AoE вокруг барда, урон × tier,
отброс × tier, закрывает Поток."
    bdrop.icon = "🎹"
    bdrop.is_sub_skill = true
    bdrop.max_range = 8.0
    bdrop.effects.append(preload("res://Logic/Skills/BardDropEffect.gd").new())
    _skills["bard_drop"] = bdrop

    # Кузница скиллов (Q36): пользовательские скиллы вливаются в реестр в конце
    # ленивой инициализации — магазин/ActionBar/каст/персист работают по id сами.
    UserSkillDBScript.load_all(_skills)
    return _skills


static func get_shop_skills() -> Dictionary:
    ## Скиллы для магазина/Кузницы: без под-приёмов стоек (Q16). Под-приём
    ## (is_sub_skill=true) выдаётся только вместе со стойкой-родителем.
    var all := get_skills()
    var out := {}
    for id in all:
        if not all[id].is_sub_skill:
            out[id] = all[id]
    return out