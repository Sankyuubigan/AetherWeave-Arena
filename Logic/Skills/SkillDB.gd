extends RefCounted

static var _skills: Dictionary = {}
static var _initialized: bool = false

static func get_skills() -> Dictionary:
    if _initialized:
        return _skills
        
    _initialized = true
    
    # 1. Огненный Шар
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
    fb.effects.append(proj)
    _skills["fireball"] = fb

    # 2. Телепорт
    var tp = preload("res://Logic/Skills/Skill.gd").new()
    tp.id = "teleport"
    tp.skill_name = "Телепорт (20м)"
    tp.description = "Мгновенное перемещение."
    tp.icon = "🌌"
    tp.price = 2
    tp.max_range = 20.0
    var tel = preload("res://Logic/Skills/TeleportEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/teleport_effect.tscn"):
        tel.vfx_scene = load("res://Scenes/teleport_effect.tscn")
    tp.effects.append(tel)
    _skills["teleport"] = tp

    # 3. Двойной прыжок
    var dj = preload("res://Logic/Skills/Skill.gd").new()
    dj.id = "double_jump"
    dj.skill_name = "Двойной прыжок"
    dj.description = "Позволяет прыгать в воздухе."
    dj.icon = "🏃"
    dj.price = 1
    dj.is_passive = true
    _skills["double_jump"] = dj
    
    # 4. Громовой раскат
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
    _skills["thunderclap"] = thunder
    
    # 5. Огненный Метеорит
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
    m_proj.offset_y = 15.0
    meteor.effects.append(m_proj)
    var m_aoe = preload("res://Logic/Skills/AoeDamageEffect.gd").new()
    m_aoe.radius = 8.0
    m_aoe.damage = 60
    if ResourceLoader.exists("res://Scenes/thunder_effect.tscn"):
        m_aoe.vfx_scene = load("res://Scenes/thunder_effect.tscn")
    meteor.effects.append(m_aoe)
    _skills["meteor"] = meteor

    # 6. Шаровая Молния
    var ball_lightning = preload("res://Logic/Skills/Skill.gd").new()
    ball_lightning.id = "ball_lightning"
    ball_lightning.skill_name = "Шаровая Молния"
    ball_lightning.description = "Самонаводящийся снаряд.\nТребует врага в прицеле.\nСкорость: 8 м/с."
    ball_lightning.icon = "🔮"
    ball_lightning.price = 4
    ball_lightning.max_range = 100.0
    ball_lightning.requires_target = true
    ball_lightning.target_type = "enemy"
    var bl_proj = preload("res://Logic/Skills/SpawnHomingProjectileEffect.gd").new()
    if ResourceLoader.exists("res://Scenes/ball_lightning.tscn"):
        bl_proj.projectile_scene = load("res://Scenes/ball_lightning.tscn")
    ball_lightning.effects.append(bl_proj)
    _skills["ball_lightning"] = ball_lightning

    # 7. Сердечко (Исцеление)
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
    heart.effects.append(h_proj)
    _skills["heart_heal"] = heart
    
    return _skills