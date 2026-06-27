extends SceneTree

func _init():
    var root = CharacterBody3D.new()
    root.name = "Player"

    var collision = CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape = CapsuleShape3D.new()
    shape.radius = 0.5
    shape.height = 2.0
    collision.shape = shape
    root.add_child(collision)
    collision.owner = root

    var wrapper = Node3D.new()
    wrapper.name = "GraphicsWrapper"
    root.add_child(wrapper)
    wrapper.owner = root

    var mesh = MeshInstance3D.new()
    mesh.name = "MeshInstance3D"
    var capsule = CapsuleMesh.new()
    capsule.radius = 0.5
    capsule.height = 2.0
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.0, 0.0, 1.0)
    capsule.material = mat
    mesh.mesh = capsule
    mesh.position.y = 1.0
    wrapper.add_child(mesh)
    mesh.owner = root

    var camera = Camera3D.new()
    camera.name = "Camera3D"
    camera.position = Vector3(0, 2.5, 4)
    camera.rotation.x = -0.35
    root.add_child(camera)
    camera.owner = root

    var controller_script = load("res://Logic/PlayerController.gd")
    root.set_script(controller_script)

    var spell_caster_script = load("res://Logic/SpellCasterComponent.gd")
    var spell_caster = Node.new()
    spell_caster.name = "SpellCasterComponent"
    spell_caster.set_script(spell_caster_script)
    root.add_child(spell_caster)
    spell_caster.owner = root

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/player.tscn")
    quit()
