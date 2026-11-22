extends SceneTree

## Генератор снаряда «Сгусток маны» (Q16 Шаг 2, паттерн build_fireball.gd):
## компактная cyan-blue сфера + шлейф. ProjectileComponent общий — урон
## множится stance_power через SpawnProjectileEffect (BASE_DAMAGE общий).

func _init():
    var root = Area3D.new()
    root.name = "ManaBolt"

    # Плотная светящаяся сфера (cyan-blue, ТЗ спеца — «сгусток маны»)
    var mesh = MeshInstance3D.new()
    mesh.name = "MeshInstance3D"
    var sphere = SphereMesh.new()
    sphere.radius = 0.15
    sphere.height = 0.3
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.9, 1.0)
    mat.emission_enabled = true
    mat.emission = Color(0.3, 0.9, 1.0)
    mat.emission_energy_multiplier = 4.0
    sphere.material = mat
    mesh.mesh = sphere
    root.add_child(mesh)
    mesh.owner = root

    var collision = CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape = SphereShape3D.new()
    shape.radius = 0.22
    collision.shape = shape
    root.add_child(collision)
    collision.owner = root

    # Шлейф (паттерн fireball: партиклы + мягкая круглая кисть)
    var trail = GPUParticles3D.new()
    trail.name = "TrailParticles"
    trail.amount = 60
    trail.lifetime = 0.5
    trail.local_coords = false

    var p_mat = ParticleProcessMaterial.new()
    p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    p_mat.emission_sphere_radius = 0.18
    p_mat.gravity = Vector3(0, 0.4, 0)
    p_mat.scale_min = 0.35
    p_mat.scale_max = 0.75

    var gradient = Gradient.new()
    gradient.colors = [Color(0.5, 1.0, 1.0, 1.0), Color(0.1, 0.4, 1.0, 0.0)]
    gradient.offsets = [0.0, 1.0]
    var grad_tex = GradientTexture1D.new()
    grad_tex.gradient = gradient
    p_mat.color_ramp = grad_tex
    trail.process_material = p_mat

    var circle_grad = Gradient.new()
    circle_grad.colors = [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
    circle_grad.offsets = [0.0, 1.0]
    var circle_tex = GradientTexture2D.new()
    circle_tex.gradient = circle_grad
    circle_tex.fill = GradientTexture2D.FILL_RADIAL
    circle_tex.fill_from = Vector2(0.5, 0.5)
    circle_tex.fill_to = Vector2(1.0, 0.5)
    circle_tex.width = 64
    circle_tex.height = 64

    var draw_mat = StandardMaterial3D.new()
    draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    draw_mat.vertex_color_use_as_albedo = true
    draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    draw_mat.albedo_texture = circle_tex

    var quad = QuadMesh.new()
    quad.material = draw_mat
    quad.size = Vector2(0.25, 0.25)
    trail.draw_pass_1 = quad
    root.add_child(trail)
    trail.owner = root

    var proj_script = load("res://Logic/ProjectileComponent.gd")
    root.set_script(proj_script)

    var packed_scene = PackedScene.new()
    packed_scene.pack(root)
    ResourceSaver.save(packed_scene, "res://Scenes/mana_bolt.tscn")
    quit()
