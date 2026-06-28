extends Node

# Теперь компонент ничего не знает про конкретные скиллы. 
# Он только готовит геометрию (Raycast) и запускает переданный Skill.

func cast_skill(skill_id: String):
    # Проверяем, существует ли скилл в глобальной базе
    if not SkillDB.skills.has(skill_id):
        return
        
    var skill = SkillDB.skills[skill_id]
    if skill.is_passive: 
        return # Пассивки нельзя скастовать кнопкой

    var player = get_parent()
    var camera = player.get_node_or_null("SpringArm3D/Camera3D")
    if not camera: 
        return

    # Подготовка Raycast для вычисления цели
    var space_state = player.get_world_3d().direct_space_state
    var cam_pos = camera.global_position
    var forward = -camera.global_transform.basis.z
    
    var end_pos = cam_pos + forward * skill.max_range
    var query = PhysicsRayQueryParameters3D.create(cam_pos, end_pos)
    query.exclude = [player.get_rid()]
    
    var result = space_state.intersect_ray(query)
    var target_point = end_pos
    var hit_normal = Vector3.UP
    var target_node = null
    
    if result and result.has("position"):
        target_point = result.position
        hit_normal = result.normal
        target_node = result.collider
        
        # Для телепорта небольшая коррекция (отступ от стены)
        if skill_id == "teleport":
            target_point += hit_normal * 1.0

    # Собираем контекст для эффектов "лего"
    var context = {
        "target_pos": target_point,
        "hit_normal": hit_normal,
        "target_node": target_node,
        "camera_pos": cam_pos,
        "forward_dir": forward
    }

    # Запускаем выполнение композиции эффектов
    skill.execute(player, context)