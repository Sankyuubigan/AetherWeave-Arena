extends SceneTree

func _init():
    var root = StaticBody3D.new()
    root.name = "Dummy"

    var mesh = MeshInstance3D.new()
    mesh.name = "MeshInstance3D"
    var capsule = CapsuleMesh.new()
    capsule.radius = 0.5
    capsule.height = 2.0
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.0, 0.0)
    capsule.material = mat
    mesh.mesh = capsule
    mesh.position.y = 1.0
    root.add_child(mesh)
    mesh.owner = root

    var collision = CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape = CapsuleShape3D.new()
    shape.radius = 0.5
    shape.height = 2.0
    collision.shape = shape
    root.add_child(collision)
    collision.owner = root

    var health_script = load("res://Logic/HealthComponent.gd")
    root.set_script(health_script)

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/dummy.tscn")
    quit()
