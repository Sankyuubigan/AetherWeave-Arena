extends RefCounted

static var _skills: Dictionary = {}
static var _initialized: bool = false

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
    
    return _skills