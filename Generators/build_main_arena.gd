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
    # Увеличиваем арену в 2 раза (до 100х100 метров), чтобы было место для бега
    arena.scale = Vector3(2, 1, 2)
    root.add_child(arena)
    arena.owner = root

    var player_scene = load("res://Scenes/player.tscn")
    var player = player_scene.instantiate()
    player.position = Vector3(0, 1, 0)
    root.add_child(player)
    player.owner = root

    var dummy_scene = load("res://Scenes/dummy.tscn")
    
    # 1. Обычный стоячий манекен
    var dummy = dummy_scene.instantiate()
    dummy.position = Vector3(0, 1, -5)
    root.add_child(dummy)
    dummy.owner = root

    # 2. Медленный манекен (Ходит по линии)
    var dummy_line = dummy_scene.instantiate()
    dummy_line.position = Vector3(-10, 1, -15)
    dummy_line.name = "DummyLine"
    # Динамически меняем скрипт прямо при сборке сцены!
    dummy_line.set_script(load("res://Logic/MovingDummy.gd"))
    dummy_line.set("move_type", "line")
    dummy_line.set("move_speed", 3.0)
    root.add_child(dummy_line)
    dummy_line.owner = root

    # 3. Быстрый манекен (Бегает треугольником)
    var dummy_tri = dummy_scene.instantiate()
    dummy_tri.position = Vector3(15, 1, -10)
    dummy_tri.name = "DummyTriangle"
    dummy_tri.set_script(load("res://Logic/MovingDummy.gd"))
    dummy_tri.set("move_type", "triangle")
    dummy_tri.set("move_speed", 8.0)
    root.add_child(dummy_tri)
    dummy_tri.owner = root

    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, "res://Scenes/MainArena.tscn")
    print("MainArena generated with moving dummies!")
    quit()