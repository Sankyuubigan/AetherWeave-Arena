extends "res://Logic/Skills/Effect.gd"

# НОВАЯ ДЕТАЛЬКА: Наносит урон всем в радиусе и спавнит эффект
const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

@export var radius: float = 5.0
@export var damage: int = 30
@export var vfx_scene: PackedScene

func apply(caster: Node, context: Dictionary) -> void:
    var target_pos: Vector3 = context.get("target_pos", caster.global_position)

    # 1. Воспроизводим визуальный эффект в точке прицела
    if vfx_scene:
        var vfx = vfx_scene.instantiate()
        var tree = caster.get_tree()
        var world = tree.current_scene if (tree and tree.current_scene) else caster.get_parent()
        world.add_child(vfx)
        vfx.global_position = target_pos

    # 1.5. Кольцо ударной волны на поверхности (аним. декаль 4.8).
    _spawn_shockwave(caster, target_pos)

    # 2. Выполняем физический запрос сферы для поиска врагов
    var space_state = caster.get_world_3d().direct_space_state
    var shape = SphereShape3D.new()
    shape.radius = radius
    
    var query = PhysicsShapeQueryParameters3D.new()
    query.shape = shape
    query.transform = Transform3D(Basis(), target_pos)
    
    # Исключаем самого игрока, чтобы он не взорвал сам себя
    if caster.has_method("get_rid"):
        query.exclude = [caster.get_rid()]
        
    var results = space_state.intersect_shape(query)
    for res in results:
        var collider = res.collider
        if collider.has_method("take_damage"):
            collider.take_damage(damage)

## Кольцо ударной волны: ищем поверхность под точкой (прицел мог быть на
## стене — тогда кольцо ляжет на неё), диаметр = 2 * radius AoE.
func _spawn_shockwave(caster: Node, target_pos: Vector3) -> void:
    var world: World3D = caster.get_world_3d()
    var ground := AnimatedDecalComponent.ground_hit_below(world, target_pos)
    var pos: Vector3
    var normal: Vector3
    if ground.is_empty():
        # Поверхности под точкой нет — кладём декаль в точке прицела, нормаль UP.
        pos = target_pos
        normal = Vector3.UP
    else:
        pos = ground.position
        normal = ground.normal
    var scene = caster.get_tree().current_scene if caster.get_tree() else null
    if not scene:
        return
    var frames := DecalFrames.shockwave_ring(Color(1.0, 0.9, 0.5))
    var decal := AnimatedDecalComponent.new()
    decal.configure(frames, 12.0, 1.6, radius * 2.0)
    scene.add_child(decal)
    decal.place(pos, normal)