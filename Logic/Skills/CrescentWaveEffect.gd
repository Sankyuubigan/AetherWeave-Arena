extends "res://Logic/Skills/Effect.gd"

## «Серп маны» (Q16 Шаг 2, ТЗ спеца): мгновенный широкий разрез — все враги
## в радиусе и горизонтальном секторе ±60° от forward кастера. Визуал —
## процедурная дуга-лента (ImmediateMesh + Tween), без внешних ассетов.

@export var radius: float = 12.0
@export var half_angle_deg: float = 60.0
@export var damage: int = 22
@export var wave_color := Color(0.3, 0.9, 1.0)

func apply(caster: Node, context: Dictionary) -> void:
    var power := float(context.get("stance_power", 1.0))
    var dmg := int(damage * power)
    var forward: Vector3 = context.get("forward_dir", -caster.global_transform.basis.z)
    var fwd_flat := Vector3(forward.x, 0.0, forward.z)
    if fwd_flat.length_squared() < 0.0001:
        fwd_flat = Vector3.FORWARD
    fwd_flat = fwd_flat.normalized()

    var space_state = caster.get_world_3d().direct_space_state
    var shape = SphereShape3D.new()
    shape.radius = radius
    var query = PhysicsShapeQueryParameters3D.new()
    query.shape = shape
    query.transform = Transform3D(Basis(), caster.global_position)
    if caster.has_method("get_rid"):
        query.exclude = [caster.get_rid()]
    var cos_limit := cos(deg_to_rad(half_angle_deg))
    var results = space_state.intersect_shape(query)
    for res in results:
        var collider = res.collider
        if not collider.has_method("take_damage"):
            continue
        var c3d := collider as Node3D
        if c3d == null:
            continue
        var to_enemy: Vector3 = c3d.global_position - caster.global_position
        var flat := Vector3(to_enemy.x, 0.0, to_enemy.z)
        if flat.length() > radius:
            continue
        if flat.length_squared() > 0.0001:
            flat = flat.normalized()
            if flat.dot(fwd_flat) < cos_limit:
                continue
        collider.take_damage(dmg, flat * 3.0)

    _spawn_crescent(caster, fwd_flat)

func _spawn_crescent(caster: Node, fwd: Vector3) -> void:
    ## Дуга-лента перед кастером: вертикальная дуга (бугром вперёд),
    ## расширяется и растворяется через Tween. Локальные вершины строятся
    ## в плоскости (forward, up), узел ориентируется по fwd кастера.
    var scene = caster.get_tree().current_scene if caster.get_tree() else null
    if not scene:
        return
    var mi := MeshInstance3D.new()
    var mesh := ImmediateMesh.new()
    var ri := 1.4
    var ro := 2.2
    var segments := 14
    mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
    for i in range(segments + 1):
        var theta := deg_to_rad(lerp(-half_angle_deg, half_angle_deg, float(i) / segments))
        var f := cos(theta)
        var u := sin(theta)
        mesh.surface_add_vertex(Vector3(f * ri, u * ri + 1.2, 0.0))
        mesh.surface_add_vertex(Vector3(f * ro, u * ro + 1.2, 0.0))
    mesh.surface_end()
    mi.mesh = mesh

    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.albedo_color = Color(wave_color.r, wave_color.g, wave_color.b, 0.85)
    mi.material_override = mat

    scene.add_child(mi)
    # Ориентация: локальная +Z = forward кастера (дуга стоит лицом к кастер).
    mi.global_transform = Transform3D(Basis(), caster.global_position)
    var target := fwd
    if target.length_squared() > 0.0001:
        mi.look_at(caster.global_position + target, Vector3.UP)

    var tw := mi.create_tween()
    tw.set_parallel(true)
    tw.tween_property(mi, "scale", Vector3(4.0, 1.15, 3.2), 0.3).from(Vector3(0.5, 0.85, 0.5))
    tw.tween_property(mat, "albedo_color:a", 0.0, 0.32)
    tw.chain().tween_callback(mi.queue_free)
