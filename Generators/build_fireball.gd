extends SceneTree

func _init():
    var root = Area3D.new()
    root.name = "Fireball"

    # Сама светящаяся сфера
    var mesh = MeshInstance3D.new()
    mesh.name = "MeshInstance3D"
    var sphere = SphereMesh.new()
    sphere.radius = 0.2
    sphere.height = 0.4
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.5, 0.0)
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.5, 0.0)
    mat.emission_energy_multiplier = 3.0
    sphere.material = mat
    mesh.mesh = sphere
    root.add_child(mesh)
    mesh.owner = root

    var collision = CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape = SphereShape3D.new()
    shape.radius = 0.3
    collision.shape = shape
    root.add_child(collision)
    collision.owner = root
    
    # === НОВЫЙ ЭФФЕКТ МАГИИ (ОГНЕННЫЙ ШЛЕЙФ) ===
    var trail = GPUParticles3D.new()
    trail.name = "TrailParticles"
    trail.amount = 80 # Больше частиц для плотности
    trail.lifetime = 0.6
    trail.local_coords = false # ВАЖНО: оставляет искры в пространстве, создавая хвост

    var p_mat = ParticleProcessMaterial.new()
    p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    p_mat.emission_sphere_radius = 0.25
    p_mat.gravity = Vector3(0, 1.5, 0) # Дым и искры слегка поднимаются
    p_mat.scale_min = 0.4
    p_mat.scale_max = 0.9

    # Цветовой градиент (От Желто-белого к Красно-прозрачному)
    var gradient = Gradient.new()
    gradient.colors = [Color(1.0, 0.9, 0.2, 1.0), Color(1.0, 0.1, 0.0, 0.0)]
    gradient.offsets = [0.0, 1.0]
    var grad_tex = GradientTexture1D.new()
    grad_tex.gradient = gradient
    p_mat.color_ramp = grad_tex
    trail.process_material = p_mat

    # Магический материал (свечение + добавление цвета)
    var draw_mat = StandardMaterial3D.new()
    draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    draw_mat.vertex_color_use_as_albedo = true
    draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

    var quad = QuadMesh.new()
    quad.material = draw_mat
    quad.size = Vector2(0.3, 0.3)
    trail.draw_pass_1 = quad
    
    root.add_child(trail)
    trail.owner = root
    # ============================================

    var proj_script = load("res://Logic/ProjectileComponent.gd")
    root.set_script(proj_script)

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/fireball.tscn")
    quit()