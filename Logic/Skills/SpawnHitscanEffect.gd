extends "res://Logic/Skills/Effect.gd"
# Хитскан: мгновенный луч от заклинателя к точке прицела.
#
# Отдельный рейкаст НЕ делает: SpellCasterComponent уже кастует луч при
# выборе цели и кладёт в context target_pos / hit_normal / target_node.
# Эффект только использует готовый результат — один луч на каст, а не два.
#
# Состав: светящийся луч на кадр-два + вспышка с источником света в точке
# попадания + опциональная анимированная Decal-метка (след попадания).
# Вся геометрия процедурная (CylinderMesh/DrawableTexture2D) — внешних ассетов нет.

const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

@export var damage: int = 30
@export var beam_color: Color = Color(0.9, 0.15, 0.1)
@export var beam_width: float = 0.06
## Сколько секунд висит луч (0.08–0.15 = «на миг»).
@export_range(0.03, 0.5) var beam_lifetime: float = 0.12
@export var offset_y: float = 1.2
@export var leave_decal: bool = true
@export var decal_size: float = 0.7
## Луч из живой позиции кисти (Effect.hand_pos) — синхронно с каст-жестом.
@export var spawn_from_hand: bool = false
## Задержка выстрела от нажатия (с): луч бьёт в момент толчка руки в клипе.
@export var spawn_delay: float = 0.0

func apply(caster: Node, context: Dictionary) -> void:
    var tree := caster.get_tree()
    if not tree:
        return
    if spawn_delay > 0.0:
        await tree.create_timer(spawn_delay).timeout
        # За время ожидания кастер мог умереть/покинуть сцену.
        if not is_instance_valid(caster) or not caster.is_inside_tree():
            return
    var parent: Node = tree.current_scene if tree.current_scene else caster.get_parent()
    if not parent:
        return

    var start: Vector3 = caster.global_position + Vector3(0, offset_y, 0)
    if spawn_from_hand:
        start = hand_pos(caster, context.get("hand", "Right"))
    var end: Vector3 = context.get("target_pos", start + Vector3.FORWARD * 50.0)
    var normal: Vector3 = context.get("hit_normal", Vector3.UP)
    var target_node: Node = context.get("target_node")

    if target_node and target_node.has_method("take_damage"):
        target_node.take_damage(damage, end - start)

    _spawn_beam(parent, start, end)
    _spawn_impact(parent, end, normal)
    print("[Hitscan] луч ", start, " → ", end,
        " | цель: ", (target_node.name if target_node else "мимо"),
        " | урон: ", damage)

func _spawn_beam(parent: Node, start: Vector3, end: Vector3) -> void:
    var length := start.distance_to(end)
    if length < 0.01:
        return
    var beam := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.height = length
    mesh.top_radius = beam_width / 2.0
    mesh.bottom_radius = beam_width / 2.0
    mesh.radial_segments = 6
    mesh.cap_top = false
    mesh.cap_bottom = false
    beam.mesh = mesh
    beam.material_override = _glow_material(beam_color)
    parent.add_child(beam)
    beam.global_position = (start + end) / 2.0
    # look_at целит -Z, а ось цилиндра — Y: поворот -90° по X кладёт Y на -Z.
    # Вторая точка нужна, потому что look_at из середины луча смотрит вдоль него.
    var up := Vector3.UP if absf(end.direction_to(start).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
    beam.look_at(end, up)
    beam.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
    var tween := beam.create_tween()
    tween.tween_interval(beam_lifetime)
    tween.tween_callback(beam.queue_free)

func _spawn_impact(parent: Node, pos: Vector3, normal: Vector3) -> void:
    var impact := Node3D.new()
    parent.add_child(impact)
    impact.global_position = pos

    var flash := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.18
    sphere.height = 0.36
    sphere.radial_segments = 12
    sphere.rings = 6
    flash.mesh = sphere
    flash.material_override = _glow_material(beam_color.lerp(Color.WHITE, 0.6))
    impact.add_child(flash)

    var light := OmniLight3D.new()
    light.omni_range = 5.0
    light.light_color = beam_color
    light.light_energy = 3.0
    impact.add_child(light)

    var tween := impact.create_tween()
    tween.set_parallel(true)
    tween.tween_property(light, "light_energy", 0.0, 0.3)
    tween.tween_property(flash, "scale", Vector3.ONE * 0.1, 0.3)
    tween.chain().tween_callback(impact.queue_free)

    if leave_decal:
        _spawn_decal(parent, pos, normal)

func _spawn_decal(parent: Node, pos: Vector3, normal: Vector3) -> void:
    # Анимированный прожог (4.8, DrawableTexture2D): бело-горячая вспышка ->
    # остывание до тёмного следа -> растворение. Кадры — DecalFrames.
    var hot := beam_color.lerp(Color.WHITE, 0.4)
    var frames := DecalFrames.beam_scorch(hot)
    var decal := AnimatedDecalComponent.new()
    decal.configure(frames, 8.0, 15.0, decal_size)
    parent.add_child(decal)
    decal.place(pos, normal)

func _glow_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 2.5
    return material
