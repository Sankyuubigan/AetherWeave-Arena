extends "res://Logic/Skills/Effect.gd"

# НОВАЯ ДЕТАЛЬКА: Наносит урон всем в радиусе и спавнит эффект
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