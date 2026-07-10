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
	arena.scale = Vector3(2, 1, 2)
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

	var dummy_line = dummy_scene.instantiate()
	dummy_line.position = Vector3(-10, 1, -15)
	dummy_line.name = "DummyLine"
	dummy_line.set_script(load("res://Logic/MovingDummy.gd"))
	dummy_line.set("move_type", "line")
	dummy_line.set("move_speed", 3.0)
	root.add_child(dummy_line)
	dummy_line.owner = root

	var dummy_poly = dummy_scene.instantiate()
	dummy_poly.position = Vector3(15, 1, -10)
	dummy_poly.name = "DummyTriangle"
	dummy_poly.set_script(load("res://Logic/MovingDummy.gd"))
	dummy_poly.set("move_type", "complex_polygon")
	dummy_poly.set("move_speed", 16.0)
	root.add_child(dummy_poly)
	dummy_poly.owner = root

	var friendly_dummy = dummy_scene.instantiate()
	friendly_dummy.position = Vector3(-15, 1, 10)
	friendly_dummy.name = "FriendlyDummy"
	friendly_dummy.set_script(load("res://Logic/FriendlyDummy.gd"))
	friendly_dummy.set("move_type", "triangle")
	friendly_dummy.set("move_speed", 12.0)
	root.add_child(friendly_dummy)
	friendly_dummy.owner = root

	var prop_paths = {
		"Boulder": { "path": "res://Graphics/Environment/Props/boulder_01/boulder_01.tscn", "pos": Vector3(5, 0, -3), "scale": Vector3(1, 1, 1) },
		"RockMoss": { "path": "res://Graphics/Environment/Props/rock_moss_set_01/rock_moss_set_01.tscn", "pos": Vector3(-5, 0, -3), "scale": Vector3(0.8, 0.8, 0.8) }
	}
	for p_name in prop_paths:
		var p = prop_paths[p_name]
		var inst = load(p.path).instantiate()
		inst.position = p.pos
		inst.scale = p.scale
		root.add_child(inst)
		inst.owner = root
		print(p_name + " placed at " + str(p.pos))

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/MainArena.tscn")
	print("MainArena generated!")
	quit()
