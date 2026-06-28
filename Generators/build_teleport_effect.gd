extends SceneTree

func _init():
    var root = Node3D.new()
    root.name = "TeleportEffect"

    # === АНИМЕ-ЭФФЕКТ ТЕЛЕПОРТА ===
    var burst = GPUParticles3D.new()
    burst.name = "Burst"
    burst.amount = 120
    burst.lifetime = 1.0
    burst.explosiveness = 0.95 # Мгновенный взрыв всех частиц
    burst.one_shot = true

    var p_mat = ParticleProcessMaterial.new()
    p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    p_mat.emission_sphere_radius = 0.8
    p_mat.direction = Vector3(0, 1, 0)
    p_mat.spread = 120.0
    p_mat.initial_velocity_min = 3.0
    p_mat.initial_velocity_max = 7.0
    p_mat.gravity = Vector3(0, -3.0, 0) # Слегка осыпаются вниз
    p_mat.scale_min = 0.1
    p_mat.scale_max = 0.4

    # Анимешный градиент магии телепорта (Ярко-фиолетовый переходит в Голубой)
    var gradient = Gradient.new()
    gradient.colors = [Color(0.8, 0.2, 1.0, 1.0), Color(0.1, 0.8, 1.0, 0.0)]
    gradient.offsets = [0.0, 1.0]
    var grad_tex = GradientTexture1D.new()
    grad_tex.gradient = gradient
    p_mat.color_ramp = grad_tex
    burst.process_material = p_mat

    # Магический материал (Аддитивное смешивание)
    var draw_mat = StandardMaterial3D.new()
    draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    draw_mat.vertex_color_use_as_albedo = true
    draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

    var quad = QuadMesh.new()
    quad.material = draw_mat
    quad.size = Vector2(0.5, 0.5)
    burst.draw_pass_1 = quad
    
    root.add_child(burst)
    burst.owner = root
    # ============================================

    # Подключаем скрипт для самоуничтожения ноды после вспышки
    var script = load("res://Graphics/VFXAutoDestroy.gd")
    root.set_script(script)

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/teleport_effect.tscn")
    quit()