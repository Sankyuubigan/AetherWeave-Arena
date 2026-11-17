extends "res://Logic/Skills/Effect.gd"

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")

@export var projectile_scene: PackedScene
@export var offset_y: float = 1.2
## Спавн от ПРАВОЙ кисти (план 17.11.26 Шаг 3) — context.cast_origin.
@export var spawn_from_hand: bool = false

func apply(caster: Node, context: Dictionary) -> void:
    if not projectile_scene:
        return

    var target = context.get("target_node")
    if not target:
        return

    var tree = caster.get_tree()
    var parent = tree.current_scene if tree and tree.current_scene else caster.get_parent()
    if not parent:
        return

    var proj = ProjectilePool.acquire(projectile_scene, parent)

    var origin: Vector3 = caster.global_position + Vector3(0, offset_y, 0)
    if spawn_from_hand and context.has("cast_origin"):
        origin = context["cast_origin"]
    proj.global_position = origin

    # Передаем цель в снаряд для работы самонаведения
    if proj.has_method("set_target"):
        proj.set_target(target)

    # Передаем кастера, чтобы избежать попадания по себе
    if proj.has_method("set_caster"):
        proj.set_caster(caster)