extends "res://Logic/HealthComponent.gd"

var move_type: String = "line"
var move_speed: float = 3.0

var waypoints: Array[Vector3] = []
var current_wp_index: int = 0
var start_pos: Vector3

func _ready():
    # Обязательно вызываем _ready() у HealthComponent, чтобы создалась полоска ХП
    super._ready()
    start_pos = global_position
    
    # Генерируем точки маршрута в зависимости от типа
    if move_type == "line":
        waypoints.append(start_pos)
        waypoints.append(start_pos + Vector3(15, 0, 0))
    elif move_type == "triangle":
        waypoints.append(start_pos)
        waypoints.append(start_pos + Vector3(15, 0, 10))
        waypoints.append(start_pos + Vector3(-5, 0, 15))
    else:
        waypoints.append(start_pos)

func _physics_process(delta):
    # Если манекен мертв, он перестает двигаться
    if is_dead or waypoints.size() < 2:
        return
        
    var target = waypoints[current_wp_index]
    var dist = global_position.distance_to(target)
    var step = move_speed * delta
    
    # Двигаемся к следующей точке
    if dist <= step:
        global_position = target
        current_wp_index = (current_wp_index + 1) % waypoints.size()
    else:
        var dir = global_position.direction_to(target)
        global_position += dir * step

# Переопределяем метод возрождения, чтобы манекен возвращался на старт
func respawn():
    super.respawn()
    global_position = start_pos
    current_wp_index = 0