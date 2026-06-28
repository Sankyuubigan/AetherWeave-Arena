extends Node

var skills: Dictionary = {}

func _ready():
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
    skills["fireball"] = fb

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
    skills["teleport"] = tp

    # 3. Двойной прыжок
    var dj = preload("res://Logic/Skills/Skill.gd").new()
    dj.id = "double_jump"
    dj.skill_name = "Двойной прыжок"
    dj.icon = "🏃"
    dj.price = 1
    dj.is_passive = true
    skills["double_jump"] = dj
    
    # 4. НОВЫЙ СКИЛЛ: Громовой раскат
    var thunder = preload("res://Logic/Skills/Skill.gd").new()
    thunder.id = "thunderclap"
    thunder.skill_name = "Громовой раскат"
    thunder.icon = "⚡"
    thunder.price = 3
    thunder.max_range = 30.0 # Дистанция каста
    
    var aoe = preload("res://Logic/Skills/AoeDamageEffect.gd").new()
    aoe.radius = 6.0
    aoe.damage = 40
    if ResourceLoader.exists("res://Scenes/thunder_effect.tscn"):
        aoe.vfx_scene = load("res://Scenes/thunder_effect.tscn")
    thunder.effects.append(aoe)
    
    skills["thunderclap"] = thunder