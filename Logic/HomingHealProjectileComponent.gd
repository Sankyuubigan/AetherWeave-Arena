extends Area3D

## Q49: слой 8 = хитбоксы желе; сердечко у него take_damage-only (heal нет) —
## контакт ничего не делает, как и с любым телом без heal().
## Назначается в _ready (в теле класса — Parse Error).

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")
const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

@export var speed: float = 10.0
@export var heal_amount: int = 5

## Q35 (юзер 19.11.26): ретаргет сытой цели — другая дружественная с неполным
## HP в этом радиусе (включая кастера); все сыты — сердечко останавливается.
const RETARGET_RADIUS := 20.0

var target: Node3D
var caster: Node3D
var current_velocity: Vector3
var alive_time: float = 0.0
var shrinking: bool = false
var base_scale: Vector3 = Vector3.ONE

# Подгружаем сцену яркого взрыва лечения
var burst_scene = preload("res://Scenes/heart_burst.tscn")

func set_target(t: Node3D):
    target = t
    if is_instance_valid(target):
        var aim_pos = target.global_position + Vector3(0, 1.0, 0)
        current_velocity = global_position.direction_to(aim_pos) * speed

func set_caster(c: Node3D):
    caster = c

func _ready():
    collision_mask = 1 | 8
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
        if is_instance_valid(target) and not _hp_full(target):
            var aim_pos = target.global_position + Vector3(0, 1.0, 0)
            var desired_dir = global_position.direction_to(aim_pos)

            var avoidance = _calculate_avoidance()
            desired_dir = (desired_dir + avoidance * 1.5).normalized()
            current_velocity = current_velocity.lerp(desired_dir * speed, delta * 3.0)
        else:
            # Q35: у цели полное HP → другая дружественная с неполным HP в
            # радиусе (включая кастера — он дружественная цель). Все сыты —
            # сердечко останавливается и висит на месте (скорость → 0).
            var nxt = _find_hurt_ally()
            if nxt:
                set_target(nxt)
            else:
                current_velocity = current_velocity.lerp(Vector3.ZERO, delta * 4.0)

    global_position += current_velocity * delta

## Q35: полное HP у цели? Игрок: player_hp/MAX_HP; мобы: current_health/max_health.
## Незнакомый узел (нет полей HP) — не перебиваем цель (false).
func _hp_full(n: Node) -> bool:
    if not is_instance_valid(n):
        return true
    if "player_hp" in n:
        var mx: int = 100
        if "MAX_HP" in n:
            mx = n.MAX_HP
        return n.player_hp >= mx
    if "current_health" in n:
        return n.current_health >= n.max_health
    return false

## Q35: ближайшая дружественная с неполным HP в радиусе RETARGET_RADIUS.
## Кандидаты: aim_targets (HealthComponent-дружественные) + группа player +
## сам caster — по заказу юзера сердечко летит и в инициатора каста.
func _find_hurt_ally() -> Node3D:
    var tree := get_tree()
    if tree == null:
        return null
    var cands := tree.get_nodes_in_group("aim_targets")
    for p in tree.get_nodes_in_group("player"):
        cands.append(p)
    if is_instance_valid(caster) and not cands.has(caster):
        cands.append(caster)
    var best: Node3D = null
    var best_d: float = RETARGET_RADIUS
    for n in cands:
        if not is_instance_valid(n) or n == self:
            continue
        if not n.has_method("heal") or n.get("is_friendly") != true:
            continue
        if ("is_dead" in n and n.is_dead) or ("is_dying" in n and n.is_dying):
            continue
        if _hp_full(n):
            continue
        var d: float = global_position.distance_to(n.global_position)
        if d < best_d:
            best_d = d
            best = n
    return best

func _calculate_avoidance() -> Vector3:
    var avoidance = Vector3.ZERO
    var space = get_world_3d().direct_space_state
    var forward = current_velocity.normalized()
    if forward.length_squared() < 0.1: return avoidance

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

    if body.has_method("heal") and body.get("is_friendly"):
        body.heal(heal_amount)
        # Создаем визуальный эффект взрыва при лечении
        if burst_scene:
            var burst = burst_scene.instantiate()
            get_tree().current_scene.add_child(burst)
            burst.global_position = global_position
        # Пульсирующий круг благословения на полу под союзником (аним. декаль 4.8).
        _spawn_blessing()

    ProjectilePool.release(self)

func _spawn_blessing():
    var scene := get_tree().current_scene if get_tree() else null
    if not scene:
        return
    var ground := AnimatedDecalComponent.ground_hit_below(get_world_3d(), global_position)
    if ground.is_empty():
        return  # Пола нет (полёт над пропастью) — декаль не спавним.
    var frames := DecalFrames.heal_pulse(Color(1.0, 0.5, 0.65))
    var decal := AnimatedDecalComponent.new()
    decal.configure(frames, 8.0, 4.0, 1.4)
    scene.add_child(decal)
    decal.place(ground.position, ground.normal)

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