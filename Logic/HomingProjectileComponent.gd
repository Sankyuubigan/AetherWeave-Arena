extends Area3D

@export var speed: float = 8.0 # 40% от 20
@export var damage: int = 35

var target: Node3D
var caster: Node3D
var current_velocity: Vector3

var alive_time: float = 0.0
var shrinking: bool = false
var base_scale: Vector3 = Vector3.ONE

func set_target(t: Node3D):
    target = t
    if is_instance_valid(target):
        # Прицеливаемся в центр манекена (учитывая, что Origin манекена внизу)
        var aim_pos = target.global_position + Vector3(0, 1.0, 0)
        current_velocity = global_position.direction_to(aim_pos) * speed

func set_caster(c: Node3D):
    caster = c

func _ready():
    body_entered.connect(_on_body_entered)
    base_scale = scale

func _physics_process(delta):
    alive_time += delta
    
    # Фаза 15 секунд поиска/жизни завершена
    if alive_time >= 15.0 and not shrinking:
        shrinking = true
        # Полностью отключаем возможность нанести урон во время исчезновения
        set_deferred("monitoring", false)
        set_deferred("monitorable", false)

    # Фаза 3 секунд исчезновения
    if shrinking:
        var shrink_progress = (alive_time - 15.0) / 3.0
        if shrink_progress >= 1.0:
            queue_free()
            return
        scale = base_scale * (1.0 - shrink_progress)
    else:
        # Логика самонаведения
        if is_instance_valid(target):
            var aim_pos = target.global_position + Vector3(0, 1.0, 0)
            var desired_dir = global_position.direction_to(aim_pos)

            # Алгоритм Steering Behavior: Уклонение от препятствий (Обход стен)
            var avoidance = _calculate_avoidance()
            desired_dir = (desired_dir + avoidance * 1.5).normalized()

            # Плавный поворот в сторону вычисленного направления
            current_velocity = current_velocity.lerp(desired_dir * speed, delta * 3.0)
            
    global_position += current_velocity * delta

# Выбрасываем лучи вперед и в стороны, чтобы обнаружить стены и обойти их
func _calculate_avoidance() -> Vector3:
    var avoidance = Vector3.ZERO
    var space = get_world_3d().direct_space_state
    
    var forward = current_velocity.normalized()
    if forward.length_squared() < 0.1: 
        return avoidance

    var right = forward.cross(Vector3.UP).normalized()
    var up = right.cross(forward).normalized()

    # 5 лучей: Прямо, право, лево, верх, низ
    var rays = [
        forward,
        (forward + right * 0.5).normalized(),
        (forward - right * 0.5).normalized(),
        (forward + up * 0.5).normalized(),
        (forward - up * 0.5).normalized()
    ]

    var query = PhysicsRayQueryParameters3D.new()
    query.collide_with_areas = false
    
    var ex_rids = [get_rid()]
    if is_instance_valid(caster) and caster.has_method("get_rid"):
        ex_rids.append(caster.get_rid())
    query.exclude = ex_rids

    for ray_dir in rays:
        query.from = global_position
        query.to = global_position + ray_dir * 3.0
        var result = space.intersect_ray(query)
        
        # Если луч нашел препятствие, но это НЕ наша цель
        if result and result.collider != target:
            var dist = global_position.distance_to(result.position)
            # Чем ближе препятствие, тем сильнее выталкивающая сила (Нормаль поверхности)
            var force = (3.0 - dist) / 3.0
            avoidance += result.normal * force

    return avoidance

func _on_body_entered(body: Node):
    if body == caster or shrinking:
        return
        
    if body.has_method("take_damage"):
        body.take_damage(damage)
        
    queue_free()