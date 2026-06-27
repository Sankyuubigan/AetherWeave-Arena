extends SceneTree

func _init():
    var root = Area3D.new()
    root.name = "Fireball"

    var mesh = MeshInstance3D.new()
    mesh.name = "MeshInstance3D"
    var sphere = SphereMesh.new()
    sphere.radius = 0.3
    sphere.height = 0.6
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.5, 0.0)
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.5, 0.0)
    mat.emission_energy_multiplier = 2.0
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

    var proj_script = load("res://Logic/ProjectileComponent.gd")
    root.set_script(proj_script)

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/fireball.tscn")
    quit()
