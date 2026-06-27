extends Node

var fireball_scene: PackedScene

func _ready():
    fireball_scene = load("res://Scenes/fireball.tscn")

func cast_skill(skill_id: String):
    if skill_id == "fireball":
        cast_fireball()
    elif skill_id == "teleport":
        cast_teleport()

func cast_fireball():
    if fireball_scene == null: return
    
    var player = get_parent()
    var camera = player.get_node("SpringArm3D/Camera3D")
    if not camera: return

    var space_state = player.get_world_3d().direct_space_state
    var cam_pos = camera.global_position
    var forward = -camera.global_transform.basis.z
    var end_pos = cam_pos + forward * 200.0
    
    var query = PhysicsRayQueryParameters3D.create(cam_pos, end_pos)
    query.exclude = [player.get_rid()]
    
    var result = space_state.intersect_ray(query)
    var target_point = end_pos
    if result and result.has("position"):
        target_point = result.position

    var fireball = fireball_scene.instantiate()
    get_tree().current_scene.add_child(fireball)
    
    fireball.global_position = player.global_position + Vector3(0, 1.2, 0)
    var direction = fireball.global_position.direction_to(target_point)
    if fireball.has_method("set_direction"):
        fireball.set_direction(direction)

func cast_teleport():
    var player = get_parent()
    var camera = player.get_node("SpringArm3D/Camera3D")
    if not camera: return

    var space_state = player.get_world_3d().direct_space_state
    var cam_pos = camera.global_position
    var forward = -camera.global_transform.basis.z
    # Телепорт максимум на 20 метров
    var end_pos = cam_pos + forward * 20.0 
    
    var query = PhysicsRayQueryParameters3D.create(cam_pos, end_pos)
    query.exclude = [player.get_rid()]
    var result = space_state.intersect_ray(query)

    var target_point = end_pos
    if result and result.has("position"):
        # Если луч врезался в стену/пол, берем позицию удара 
        # и отступаем на 1 метр по нормали поверхности, чтобы не застрять в текстурах
        target_point = result.position + result.normal * 1.0

    player.global_position = target_point
    player.velocity = Vector3.ZERO # Сбрасываем инерцию