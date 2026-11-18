extends SceneTree
## Генератор сцены ада (19.11.26): статичная часть — окружение (багровый
## туман/амбимент) и тусклый красный свет. Тяжёлое (рельеф, скаттер, лава,
## враги) генерирует рантайм-скрипт Logic/HellArena.gd — паттерн ProceduralArena.
## Запуск: --headless -s res://Generators/build_hell_arena.gd

func _init():
	var root = Node3D.new()
	root.name = "HellArena"
	root.set_script(load("res://Logic/HellArena.gd"))

	var env_node = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.015, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.12, 0.09)
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.06, 0.04)
	env.fog_density = 0.008
	env.ssao_enabled = true
	env_node.environment = env
	root.add_child(env_node)
	env_node.owner = root

	var light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_color = Color(1.0, 0.45, 0.35)
	light.light_energy = 0.5
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/HellArena.tscn")
	print("HellArena generated!")
	quit()
