extends SceneTree

func _init():
    var root = Node3D.new()
    root.name = "MainArena"

    var env_node = WorldEnvironment.new()
    env_node.name = "WorldEnvironment"
    var env = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.4, 0.6, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.3, 0.3, 0.4)
    env_node.environment = env
    root.add_child(env_node)
    env_node.owner = root

    var light = DirectionalLight3D.new()
    light.name = "DirectionalLight3D"
    light.rotation_degrees = Vector3(-35, 45, 0)
    light.light_energy = 1.5
    light.shadow_enabled = true
    root.add_child(light)
    light.owner = root

    var arena_scene = load("res://Scenes/arena.tscn")
    var arena = arena_scene.instantiate()
    root.add_child(arena)
    arena.owner = root

    var player_scene = load("res://Scenes/player.tscn")
    var player = player_scene.instantiate()
    player.position = Vector3(0, 1, 0)
    root.add_child(player)
    player.owner = root

    var dummy_scene = load("res://Scenes/dummy.tscn")
    var dummy = dummy_scene.instantiate()
    dummy.position = Vector3(0, 1, -5)
    root.add_child(dummy)
    dummy.owner = root

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/MainArena.tscn")
    quit()
