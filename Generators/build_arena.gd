extends SceneTree

func _init():
    var root = StaticBody3D.new()
    root.name = "Arena"

    var mesh = MeshInstance3D.new()
    mesh.name = "MeshInstance3D"
    var box = BoxMesh.new()
    box.size = Vector3(50, 1, 50)
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.5, 0.5, 0.5)
    box.material = mat
    mesh.mesh = box
    mesh.position.y = -0.5
    root.add_child(mesh)
    mesh.owner = root

    var collision = CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape = BoxShape3D.new()
    shape.size = Vector3(50, 1, 50)
    collision.shape = shape
    collision.position.y = -0.5
    root.add_child(collision)
    collision.owner = root

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/arena.tscn")
    quit()
