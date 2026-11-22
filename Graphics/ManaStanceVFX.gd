extends Node

## Вход-вайб стойки «Концентрация маны» (Q16 Шаг 2, MVP): вспышка-частицы
## у кулаков на входе стойки. Реагирует ТОЛЬКО на mana_concentration.
## Паттерн частиц — build_mana_bolt (мягкая круглая кисть, additive).

const EFFECT = preload("res://Logic/Skills/Effect.gd")

func _ready() -> void:
    call_deferred("_hook")

func _hook() -> void:
    var stance = get_parent().get_node_or_null("StanceComponent")
    if stance == null:
        return
    if not stance.stance_entered.is_connected(_on_stance_entered):
        stance.stance_entered.connect(_on_stance_entered)

func _on_stance_entered(_overrides: Dictionary, stance_skill_id: String) -> void:
    if stance_skill_id != "mana_concentration":
        return
    var caster := get_parent() as Node3D
    if caster == null:
        return
    for side in ["Left", "Right"]:
        _spawn_flash(EFFECT.hand_pos(caster, side))

func _spawn_flash(pos: Vector3) -> void:
    var tree := get_tree()
    var scene = tree.current_scene if tree else null
    if scene == null:
        return
    var p := GPUParticles3D.new()
    p.one_shot = true
    p.explosiveness = 1.0
    p.amount = 26
    p.lifetime = 0.55

    var m := ParticleProcessMaterial.new()
    m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    m.emission_sphere_radius = 0.22
    m.direction = Vector3(0, 1, 0)
    m.spread = 35.0
    m.initial_velocity_min = 1.2
    m.initial_velocity_max = 2.6
    m.gravity = Vector3(0, 2.2, 0)
    m.scale_min = 0.3
    m.scale_max = 0.7

    var grad := Gradient.new()
    grad.colors = [Color(0.5, 1.0, 1.0, 1.0), Color(0.1, 0.4, 1.0, 0.0)]
    grad.offsets = [0.0, 1.0]
    var ramp := GradientTexture1D.new()
    ramp.gradient = grad
    m.color_ramp = ramp
    p.process_material = m

    var ctex := GradientTexture2D.new()
    var cgrad := Gradient.new()
    cgrad.colors = [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
    cgrad.offsets = [0.0, 1.0]
    ctex.gradient = cgrad
    ctex.fill = GradientTexture2D.FILL_RADIAL
    ctex.fill_from = Vector2(0.5, 0.5)
    ctex.fill_to = Vector2(1.0, 0.5)
    ctex.width = 64
    ctex.height = 64

    var dm := StandardMaterial3D.new()
    dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    dm.vertex_color_use_as_albedo = true
    dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    dm.albedo_texture = ctex

    var quad := QuadMesh.new()
    quad.material = dm
    quad.size = Vector2(0.14, 0.14)
    p.draw_pass_1 = quad

    scene.add_child(p)
    p.global_position = pos
    p.emitting = true
    var tw := p.create_tween()
    tw.tween_interval(1.0)
    tw.tween_callback(p.queue_free)
