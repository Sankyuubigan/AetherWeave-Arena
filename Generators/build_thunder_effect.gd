extends SceneTree

func _init():
    var root = Node3D.new()
    root.name = "ThunderEffect"

    var burst = GPUParticles3D.new()
    burst.name = "Burst"
    burst.amount = 150
    burst.lifetime = 0.5
    burst.explosiveness = 1.0 # Мгновенный взрыв
    burst.one_shot = true

    var p_mat = ParticleProcessMaterial.new()
    p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    p_mat.emission_sphere_radius = 5.0 # Широкий радиус (соответствует радиусу урона)
    p_mat.direction = Vector3(0, 1, 0)
    p_mat.spread = 180.0
    p_mat.initial_velocity_min = 5.0
    p_mat.initial_velocity_max = 15.0
    
    # Молния: Переход от ярко-голубого к прозрачному
    var gradient = Gradient.new()
    gradient.colors = [Color(0.2, 0.8, 1.0, 1.0), Color(0.1, 0.1, 1.0, 0.0)]
    gradient.offsets = [0.0, 1.0]
    var grad_tex = GradientTexture1D.new()
    grad_tex.gradient = gradient
    p_mat.color_ramp = grad_tex
    burst.process_material = p_mat

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

    var script = load("res://Graphics/VFXAutoDestroy.gd")
    root.set_script(script)

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/thunder_effect.tscn")
    print("Thunder effect scene generated!")
    quit()