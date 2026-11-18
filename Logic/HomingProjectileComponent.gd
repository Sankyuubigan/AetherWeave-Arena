extends Area3D

# Снизил скорость шаровой молнии до 6 м/с
const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")
const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

@export var speed: float = 6.0
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
        var aim_pos = target.global_position + Vector3(0, 1.0, 0)
        current_velocity = global_position.direction_to(aim_pos) * speed

func set_caster(c: Node3D):
    caster = c

func _ready():
    body_entered.connect(_on_body_entered)
    base_scale = scale

func _physics_process(delta):
    alive_time += delta
    
    if alive_time >= 15.0 and not shrinking:
        shrinking = true
        set_deferred("monitoring", false)
        set_deferred("monitorable", false)

    if shrinking:
        var shrink_progress = (alive_time - 15.0) / 3.0
        if shrink_progress >= 1.0:
            ProjectilePool.release(self)
            return
        scale = base_scale * (1.0 - shrink_progress)
    else:
        if is_instance_valid(target):
            var aim_pos = target.global_position + Vector3(0, 1.0, 0)
            var desired_dir = global_position.direction_to(aim_pos)

            var avoidance = _calculate_avoidance()
            desired_dir = (desired_dir + avoidance * 1.5).normalized()

            current_velocity = current_velocity.lerp(desired_dir * speed, delta * 3.0)
            
    global_position += current_velocity * delta

func _calculate_avoidance() -> Vector3:
    var avoidance = Vector3.ZERO
    var space = get_world_3d().direct_space_state
    
    var forward = current_velocity.normalized()
    if forward.length_squared() < 0.1: 
        return avoidance

    var right = forward.cross(Vector3.UP).normalized()
    var up = right.cross(forward).normalized()

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
        
        if result and result.collider != target:
            var dist = global_position.distance_to(result.position)
            var force = (3.0 - dist) / 3.0
            avoidance += result.normal * force

    return avoidance

func _on_body_entered(body: Node):
    if body == caster or shrinking:
        return

    if body.has_method("take_damage"):
        body.take_damage(damage, current_velocity)

    # Электрический прожог (аним. декаль 4.8): мигающие дуги -> угасание.
    # Спавн ДО release — декаль живёт в current_scene независимо от пула.
    var scene := get_tree().current_scene if get_tree() else null
    if scene:
        var normal := AnimatedDecalComponent.surface_normal(
            get_world_3d(), global_position,
            current_velocity if current_velocity.length_squared() > 0.001 else Vector3.DOWN,
            Vector3.UP)
        var frames := DecalFrames.electric_scorch(Color(0.3, 0.85, 1.0))
        var decal := AnimatedDecalComponent.new()
        decal.configure(frames, 10.0, 4.0, 1.4)
        scene.add_child(decal)
        decal.place(global_position, normal)

    ProjectilePool.release(self)

func pooled_reset():
    # Полный сброс полёта: _ready при переиспользовании не вызывается.
    target = null
    caster = null
    current_velocity = Vector3.ZERO
    alive_time = 0.0
    shrinking = false
    scale = base_scale
    # Шлейф Trail3D: сброс истории при переиспользовании из пула.
    var ribbon := get_node_or_null("TrailRibbon")
    if ribbon and ribbon.has_method("clear"):
        ribbon.clear()