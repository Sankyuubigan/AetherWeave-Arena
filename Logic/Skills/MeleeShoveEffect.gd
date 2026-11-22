extends "res://Logic/Skills/Effect.gd"

## Мили-эффект «Сокрушение маны» (Q16 Шаг 2, ТЗ спеца): урон и рэгдолл-отброс
## в сфере ПЕРЕД кастером на фиксированной дистанции (НЕ точка прицела).
## Кольцо ударной волны — готовый аним-декаль (паттерн AoeDamageEffect).

const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

@export var damage: int = 30
@export var reach: float = 2.5
@export var radius: float = 2.8
@export var shove_force: float = 9.0

func apply(caster: Node, context: Dictionary) -> void:
    var power := float(context.get("stance_power", 1.0))
    var dmg := int(damage * power)
    var forward: Vector3 = context.get("forward_dir", -caster.global_transform.basis.z)
    var fwd_flat := Vector3(forward.x, 0.0, forward.z)
    if fwd_flat.length_squared() < 0.0001:
        fwd_flat = Vector3.FORWARD
    fwd_flat = fwd_flat.normalized()

    var center: Vector3 = caster.global_position + fwd_flat * reach + Vector3(0, 1.0, 0)
    _spawn_shockwave(caster, center)

    var space_state = caster.get_world_3d().direct_space_state
    var shape = SphereShape3D.new()
    shape.radius = radius
    var query = PhysicsShapeQueryParameters3D.new()
    query.shape = shape
    query.transform = Transform3D(Basis(), center)
    if caster.has_method("get_rid"):
        query.exclude = [caster.get_rid()]
    var results = space_state.intersect_shape(query)
    for res in results:
        var collider = res.collider
        if not collider.has_method("take_damage"):
            continue
        var c3d := collider as Node3D
        var shove := Vector3.ZERO
        if c3d:
            shove = c3d.global_position - caster.global_position
            shove.y = 0.0
            if shove.length_squared() > 0.0001:
                shove = shove.normalized() * shove_force * power
        collider.take_damage(dmg, shove)

func _spawn_shockwave(caster: Node, target_pos: Vector3) -> void:
    var world: World3D = caster.get_world_3d()
    var ground := AnimatedDecalComponent.ground_hit_below(world, target_pos)
    var pos := target_pos
    var normal := Vector3.UP
    if not ground.is_empty():
        pos = ground.position
        normal = ground.normal
    var scene = caster.get_tree().current_scene if caster.get_tree() else null
    if not scene:
        return
    var frames := DecalFrames.shockwave_ring(Color(0.3, 0.9, 1.0))
    var decal := AnimatedDecalComponent.new()
    decal.configure(frames, 12.0, 1.6, radius * 2.0)
    scene.add_child(decal)
    decal.place(pos, normal)
