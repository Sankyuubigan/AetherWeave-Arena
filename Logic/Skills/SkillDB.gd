extends RefCounted

static var _skills: Dictionary = {}
static var _initialized: bool = false

# Статическая функция для получения всех скиллов.
# Она срабатывает только один раз при первом обращении.
static func get_skills() -> Dictionary:
    if _initialized:
        return _skills
        
    _initialized = true
    
    # 1. Огненный Шар
    var fb = preload("res://Logic/Skills/Skill.gd").new()
    fb.id = "fireball"
    fb.skill_name = "Огненный Шар"
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
    dj.icon = "🏃"
    dj.price = 1
    dj.is_passive = true
    _skills["double_jump"] = dj
    
    # 4. Громовой раскат (только AoE)
    var thunder = preload("res://Logic/Skills/Skill.gd").new()
    thunder.id = "thunderclap"
    thunder.skill_name = "Громовой раскат"
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
    
    # 5. Огненный Метеорит (Снаряд + AoE)
    var meteor = preload("res://Logic/Skills/Skill.gd").new()
    meteor.id = "meteor"
    meteor.skill_name = "Огненный Метеорит"
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
    
    return _skills