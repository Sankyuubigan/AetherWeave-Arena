extends RefCounted

static var _skills: Dictionary = {}
static var _initialized: bool = false

# Кузница скиллов (Q36): персист пользовательских скиллов (user://custom_skills.json).
const UserSkillDBScript := preload("res://Logic/Skills/UserSkillDB.gd")
const SkillBranchDBScript := preload("res://Logic/Skills/SkillBranchDB.gd")

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
    proj.spawn_from_hand = true  # инста-каст из кисти бросающей руки
    # Спавн в момент ВЫБРОСА руки. Клип Cast_1H_Magic_01 (утверждён юзером
    # 26.11.26 по кандидату /tools/candidates_models/Standing_1H_Magic_Attack_01.glb).
    # ЗАМЕР ЗАНОВО 26.11.26 (Generators/probe_hand_axis.gd, ось +Z = вперёд —
    # модель Mixamo смотрит в +Z, docs/cast_pipeline.md §7.1):
    #   ПРАВАЯ кисть пик z=+0.77 на t=1.33; на t=1.40 правая z=+0.75,
    #   ЛЕВАЯ z=−0.45 (УХОДИТ ЗА СПИНУ).
    # Старый замер (probe_hand_extent) считал «вперёд» как −Z и дал ЗЕРКАЛЬНЫЙ
    # вывод «бросает левая» → снаряд вылетал из руки за спиной (жалоба юзера
    # «фаербол с неправильной руки, которая сзади»). Теперь правая.
    # cast_speed 2.0 (просьба юзера «ускорить раза в 2»): клип идёт 1.15 с,
    # поэтому спавн = 1.33 / 2 ≈ 0.67 с РЕАЛЬНОГО времени.
    proj.spawn_delay = 0.67
    fb.effects.append(proj)
    # Инста-каст-анимация (26.11.26): импортёр import_manifest_casts.gd принёс
    # клип из манифеста — вместо акробатического UAL Throw.
    fb.cast_anim = "Cast_1H_Magic_01"
    # Рука бросает ПРАВАЯ (замер выше) — снаряд из неё же (context["hand"]).
    fb.cast_hand = "Right"
    # Вдвое быстрее: 2.30 с → 1.15 с (проверено Generators/probe_cast_speed.gd).
    fb.cast_speed = 2.0
    # Окно отмены 70 %: выброс на 58 % длины клипа (1.33/2.30), отменять раньше
    # нельзя — спам обрывал бы сам бросок (§14.3: окно после продуктивной части).
    # cancel_at — ДОЛЯ длины, от темпа не зависит; оставляем 0.7.
    fb.cancel_at = 0.7
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
    # Магическое исчезновение (26.11.26, решение юзера): Dismissing_Gesture
    # вперёд + он же РЕВЕРСОМ на прибытии (TeleportEffect играет Appear сам —
    # он один знает момент приземления). 2.23 с в свип 0.6 с → темп 3.0
    # (0.74 с): жест заканчивается вместе с прибытием, а не висит поверх.
    tp.cast_anim = "Teleport_Vanish"
    tp.cast_speed = 3.0
    tp.cancel_at = 0.75   # окно после исчезновения: обрывать свип нельзя
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
    # Каст-клип канала (26.11.26, решение юзера): двуручный магический удар
    # (Standing_2H_Magic_Attack_01). Канал играет его ОДИН раз, растянутый в
    # окно cast_time (2.70 с → 1.0 с, темп 2.7): удар клипа = момент execute().
    thunder.cast_anim = "Cast_2H_Magic_01"
    thunder.cast_hand = "Right"
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
    # Каст-клип канала (26.11.26, решение юзера): двуручный AoE-замах
    # (Standing_2H_Magic_Area_Attack_01). Один раз, растянут в окно канала
    # (2.97 с → 2.0 с, темп 1.49): удар клипа = падение метеора (execute()).
    meteor.cast_anim = "Cast_2H_Area_01"
    meteor.cast_hand = "Right"
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
    # Спавн в момент «выброса»: Cast_2H_Push держит кисти впереди с t≈0.07
    # до конца клипа (0.63 с), поэтому задержка может быть небольшой — сердце
    # рождается уже из выброшенных ладоней.
    # ЗАМЕР через РЕАЛЬНЫЙ путь (Generators/probe_heart_profile.gd):
    #   t=0.07 → R fwd=+0.45 откл 1°, L fwd=+0.41 откл 4°;
    #   t=0.20 → R 0°, L 6°;  t=0.40 → R 1°, L 9°  — весь клип «вперёд».
    # Прежние задержки (0.30, затем 0.85) относились к Spell_Cast, чей жест
    # уводил кисти ВБОК к середине клипа — см. комментарий у cast_anim ниже.
    h_proj.spawn_delay = 0.12
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
    # КЛИП (27.11.26, по замеру через РЕАЛЬНЫЙ путь воспроизведения —
    # Generators/render_heart_real.gd и probe_heart_profile.gd):
    #   Cast_2H_Push — обе кисти ВПЕРЁД и ПО ЦЕНТРУ весь клип
    #   (R x=+0.01 fwd=+0.40 откл 1°, L x=+0.05 fwd=+0.36 откл 9°), 0.63 с.
    #   Прежний Spell_Cast уводил кисти ВБОК к середине клипа
    #   (t=0.85: R 47°, L 65°) — юзер видел «рука в бок, не прямо».
    # Данные клипа — UAL Pistol_Shoot; в каст-библиотеку он кладётся под
    # СМЫСЛОВЫМ именем Cast_2H_Push, потому что имя «пистолет» юзер отверг
    # (docs/animation_generation.md §16.17). Генератор: import_cast_clips.gd.
    # ГЕЙТ: Generators/probe_spawn_sync.gd мерит РЕАЛЬНЫЙ путь (CastAnimationLayer
    # + aim-модификатор), а не сырую библиотеку — иначе замеры расходятся с игрой.
    heart.cast_anim = "Cast_2H_Push"
    # ЧЕРЕДОВАНИЕ РУК ОТКЛЮЧЕНО (27.11.26) — это была вторая половина бага.
    # alternate_hands рождал сердце то из правой кисти (x≈+0.3), то из левой
    # (x≈−0.3): снаряд вылетал по диагонали в РАЗНЫЕ стороны — ровно то, что
    # юзер описал как «сердечко в бок то вправо то влево». У двуручного толчка
    # обе ладони впереди и по центру, чередовать нечего: сердце всегда ПРЯМО.
    heart.alternate_hands = false
    heart.cast_hand = "Right"
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
    # Анимации (26.11.26, вердикт юзера «не отменять удары, а ставить в
    # очередь»): режим ВЗМАХА ведёт каст-слой — A → B → A по окну отмены.
    # Материализацию (Throw) выбирает эффект хуком pick_cast_anim: клинка нет
    # → Throw, есть → A/B. Окно отмены 0.6 (клип 0.43 с): спам встаёт в
    # очередь, а не рестартит удар.
    bl.cast_anim = "Blade_Swing_A"
    bl.next_cast_anim = "Blade_Swing_B"
    bl.cancel_at = 0.6
    bl.effects.append(preload("res://Logic/Skills/SpawnBladeEffect.gd").new())
    _skills["energy_blade"] = bl

    # Крылья ускорения (Q20, спец-батч 19.11.26): светящиеся крылья на 10 с,
    # пока активны — скорость x1.35 (fov + линии скорости как спринт Minecraft).
    var wg = preload("res://Logic/Skills/Skill.gd").new()
    wg.id = "wings"
    wg.skill_name = "Крылья ускорения"
    wg.description = "Светящиеся крылья на 10 с.
Пока раскрыты — скорость +35% и рывок обзора."
    wg.icon = "🕊"  # U+1FABD 🪽 не рендерился в Win10 (белый квадрат) — фикс Q16 Шаг 9
    wg.price = 2
    wg.max_range = 200.0
    # Анимация полёта (26.11.26, баг «на крыльях ничего не стоит»): клип
    # Flying.fbx (mixamo://Flying.fbx, loop) — клип-СОСТОЯНИЕ, играет по кругу
    # пока крылья активны. cast_anim_loop=true → каст-слой не даёт окна отмены
    # и не перезапускает позу спамом; WingsComponent.deactivate гасит клип сам.
    wg.cast_anim = "Wings_Fly"
    wg.cast_anim_loop = true
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
    # Каст-клип (26.11.26, решение юзера): Standing_2H_Cast_Spell_01 —
    # двуручное сотворение портала (2.17 с). Окно отмены 0.75 — после броска рук.
    ptl.cast_anim = "Cast_2H_Spell"
    ptl.cancel_at = 0.75
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
    # Каст-клип (26.11.26, решение юзера): тот же двуручный жест, что у v1.
    ptl2.cast_anim = "Cast_2H_Spell"
    ptl2.cancel_at = 0.75
    ptl2.effects.append(preload("res://Logic/Skills/SpawnPortals2Effect.gd").new())
    var pts2 = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    pts2.audio_stream = load("res://Audio/SFX/neural_teleport.res")
    pts2.volume_db = 0.0
    ptl2.effects.append(pts2)
    _skills["portals2"] = ptl2

    # Эфирный захват (Q48, ТЗ 21.11.26 / PRP tasks/tether_swing_prp.md):
    # магический трос — зацеп за точку прицела или воздушный эфирный якорь,
    # маятник-свинг / рывок-зип, инерция после отрыва. Паттерн Blade/Wings:
    # cast_anim="" (жест Cast_Shoot играет эффект), повторный каст в полёте =
    # срыв с бустом. В SkillSerializer не добавляем — встроенный скилл.
    var eth = preload("res://Logic/Skills/Skill.gd").new()
    eth.id = "ether_tether"
    eth.skill_name = "Эфирный захват"
    eth.description = "Магический трос: зацеп за точку прицела
(или за воздух — эфирный якорь) и скоростной маятник.
Повторный каст в полёте — срыв с бустом. Пробел — отрыв."
    eth.icon = "🕸"  # 🪝 (U+1FA9D) не рендерился в Win10 — как 🪽 в Q16 Шаг 9
    eth.price = 3
    eth.max_range = 45.0
    # Анимация полёта на тросе (26.11.26, решение юзера): Tether_Hang
    # (Hanging_Idle_2, loop) — клип-СОСТОЯНИЕ, играет по кругу, пока трос
    # активен. Жест ЗАЦЕПА (Cast_Shoot) остаётся у эффекта: он один знает,
    # зацепился ли трос (промах рейкаста = зацепа нет, поза не нужна).
    # cast_anim_loop НЕ ставим: скилл не должен крутить позу до зацепа —
    # TetherSwingComponent включает loop сам в момент зацепа.
    eth.cast_anim = ""
    eth.cast_hand = "Left"  # Cast_Shoot — леворукий клип (как beam/ball_lightning)
    eth.effects.append(preload("res://Logic/Skills/TetherSwingEffect.gd").new())
    var eth_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    eth_sound.audio_stream = load("res://Audio/SFX/neural_teleport.res")
    eth_sound.volume_db = 0.0
    eth.effects.append(eth_sound)
    _skills["ether_tether"] = eth

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
    mconc.cooldown = 2.0  # В.6.4 (вердикт спеца): КД повторного входа, тестовый
    _skills["mana_concentration"] = mconc

    # Стойка «Поток Гармонии» (Q16 Шаг 6, R-скилл): ритм-куполов-стойка барда.
    var bflow = preload("res://Logic/Skills/Skill.gd").new()
    bflow.id = "bard_flow"
    bflow.skill_name = "Поток Гармонии"
    bflow.description = "Стойка-концерт: ЛКМ в такт нот слева, ПКМ — аккорды справа.
Каст только за попадание: Perfect ×1.25 / Good ×0.85, мимо — фальшивая нота и штраф.
Топливо 5 с: Perfect +1.2 / Good +0.5 / Miss −0.5 / пустой пресс −1.2 (−1 tier), потолок 60 с.
Купол поглощает урон (15→50% по tier), рикошет 15→60%. Esc/Бас-Дроп — выход."
    bflow.icon = "🎵"  # U+1FABD 🪽 не рендерился в Win10 (белый квадрат) — фикс Q16 Шаг 9
    bflow.price = 5
    bflow.max_range = 200.0
    # Клип-СОСТОЯНИЕ стойки (26.11.26, решение юзера): Guitar_Playing1 —
    # бард играет на гитаре, пока Поток Гармонии активен. Отдельное поле
    # stance_loop_anim: у стойки нет каста-удара, SpellCaster не при делах,
    # StanceComponent включает на входе и гасит на выходе.
    bflow.stance_loop_anim = "Bard_Guitar"
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
        {"id": "bard_note", "label": "Ноты Гармонии", "default_slot": "ЛКМ", "judge_kind": "harmony"},
        {"id": "bard_chord", "label": "Ударный Аккорд", "default_slot": "ПКМ", "judge_kind": "chord"},
        {"id": "bard_drop", "label": "Бас-Дроп", "default_slot": "self"},
    ]
    bflow.stance_sub_skills = b_subs
    bflow.stance_rhythm_gate = true  # В.1.3 (вердикт спеца): каст только за попадание
    bflow.cooldown = 2.0  # В.6.4: КД повторного входа (тестовый; PvP потом 12–15 с)
    _skills["bard_flow"] = bflow

    # Под-приёмы Потока (Q16 Шаг 6).
    var bnote = preload("res://Logic/Skills/Skill.gd").new()
    bnote.id = "bard_note"
    bnote.skill_name = "Ноты Гармонии"
    bnote.description = "ЛКМ в такт — консонансная нота пентатоники.
Каст только за попадание в ноту левой дорожки: Perfect +1.2 с топлива (×1.25), Good +0.5 (×0.85)."
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
    # Звук аккорда (плейтест 22.11.26: ПКМ-попадание было немым).
    bchord.effects.append(preload("res://Logic/Skills/BardChordEffect.gd").new())
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

    # Стойка «Пульс Битвы» (22.11.26, спец 11-ответ Блоки 2–3): вторая стойка
    # барда — ритм на ВСЕ действия (Hi-Fi Rush): ЛЮБОЙ скилл в бит заряжает
    # Грув и получает ×1.0..1.35 урона по tier. БЕЗ падающих нот/дорожек.
    var bgroove = preload("res://Logic/Skills/Skill.gd").new()
    bgroove.id = "bard_groove"
    bgroove.skill_name = "Пульс Битвы"
    bgroove.description = "Стойка-грув: ЛЮБОЙ скилл/шаг в бит заряжает
шкалу (1 бит = 1 заряд) и усиливает урон по tier (×1.0→1.35).
ЛКМ — Нота-пуля, ПКМ — Ритм-выпад, кнопка стойки — Крещендо (от 60%).
Купол 100 (+10 за perfect), спад 11%/с, потолок 16 с. Esc — отмена."
    bgroove.icon = "🎶"
    bgroove.price = 5
    bgroove.max_range = 200.0
    # Клип-СОСТОЯНИЕ стойки (26.11.26, решение юзера): Guitar_Playing_2 —
    # вторая гитарная тема под «Пульс Битвы» (другой клип, чтобы стойки
    # различались на глаз).
    bgroove.stance_loop_anim = "Bard_Guitar_2"
    var g_ent = preload("res://Logic/Skills/EnterStanceEffect.gd").new()
    g_ent.stance_id = "bard_groove"
    # Реальный выход: groove_empty / barrier_break / max_duration(16 c) /
    # crescendo / cancel — duration 99 только страховка (как у bard_flow).
    g_ent.duration = 99.0
    bgroove.effects.append(g_ent)
    var g_sound = preload("res://Logic/Skills/PlaySoundEffect.gd").new()
    g_sound.audio_stream = load("res://Audio/Bard/note_a4.res")
    g_sound.volume_db = 0.0
    bgroove.effects.append(g_sound)
    var g_subs: Array[Dictionary] = [
        {"id": "groove_pulse", "label": "Нота-пуля", "default_slot": "ЛКМ"},
        {"id": "groove_step", "label": "Ритм-выпад", "default_slot": "ПКМ"},
        {"id": "groove_crescendo", "label": "Крещендо", "default_slot": "self"},
    ]
    bgroove.stance_sub_skills = g_subs
    # Ритм-судья НОТ не участвует (sub_kinds пуст): вердикты даёт
    # BardGrooveComponent.evaluate_action через хук cast_skill.
    bgroove.cooldown = 2.0  # КД повторного входа (как bard_flow)
    _skills["bard_groove"] = bgroove

    # Под-приёмы «Пульса Битвы».
    var gpulse = preload("res://Logic/Skills/Skill.gd").new()
    gpulse.id = "groove_pulse"
    gpulse.skill_name = "Нота-пуля"
    gpulse.description = "Лёгкий снаряд (14 урона) под стрельбу 1 раз в бит.
В бит — золотая, быстрее, ×1.25; мимо — «фальшивый» плевок ×0.4."
    gpulse.icon = "🎵"
    gpulse.is_sub_skill = true
    gpulse.max_range = 100.0
    gpulse.cooldown = 0.25
    gpulse.effects.append(preload("res://Logic/Skills/GroovePulseEffect.gd").new())
    _skills["groove_pulse"] = gpulse

    var gstep = preload("res://Logic/Skills/Skill.gd").new()
    gstep.id = "groove_step"
    gstep.skill_name = "Ритм-выпад"
    gstep.description = "Резкий стрейф-рывок 3.5 м по WASD (или вперёд).
В бит — длиннее (4.5 м) и со шлейфом нот на полу."
    gstep.icon = "💃"
    gstep.is_sub_skill = true
    gstep.max_range = 10.0
    gstep.cooldown = 0.45
    gstep.effects.append(preload("res://Logic/Skills/GrooveStepEffect.gd").new())
    _skills["groove_step"] = gstep

    var gcres = preload("res://Logic/Skills/Skill.gd").new()
    gcres.id = "groove_crescendo"
    gcres.skill_name = "Крещендо"
    gcres.description = "Финал Пульса: AoE-взрыв ∝ Груву (от 60%),
отброс по шкале, закрывает стойку."
    gcres.icon = "🥁"
    gcres.is_sub_skill = true
    gcres.max_range = 8.0
    gcres.effects.append(preload("res://Logic/Skills/GrooveCrescendoEffect.gd").new())
    _skills["groove_crescendo"] = gcres

    # Кузница скиллов (Q36): пользовательские скиллы вливаются в реестр в конце
    # ленивой инициализации — магазин/ActionBar/каст/персист работают по id сами.
    UserSkillDBScript.load_all(_skills)
    # Ветки умений (Q50): метаданные (имя-отображение, ветка) поверх кода —
    # админка (admin/start_admin.bat), файл Data/skill_branches.json.
    SkillBranchDBScript.apply_from_file(_skills)
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