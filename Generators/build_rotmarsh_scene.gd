extends SceneTree
## Генератор сцены «Гнилодолье» (Q49, 22.11.26): статичная часть — окружение
## (гнило-зелёный туман/амбимент) и мутный свет. Тяжёлое (рельеф-террасы,
## скаттер, руины, стаи желе) генерирует рантайм-скрипт Logic/RotmarshArena.gd
## — паттерн HellArena. Запуск: --headless -s res://Generators/build_rotmarsh_scene.gd

const ArenaSky = preload("res://Graphics/ArenaSky.gd")

func _init():
	var root = Node3D.new()
	root.name = "RotmarshArena"
	root.set_script(load("res://Logic/RotmarshArena.gd"))

	var env_node = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.13, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.28, 0.20)
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.34, 0.22)
	env.fog_density = 0.010
	env.fog_sky_affect = 0.15 # небо не заливать (грабля из ада: плоская заливка)
	env.ssao_enabled = true
	ArenaSky.apply(env, "rotmarsh") # гнилая мгла с низкими тучами
	env_node.environment = env
	root.add_child(env_node)
	env_node.owner = root

	var light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-38, 25, 0)
	light.light_color = Color(0.92, 0.95, 0.82) # мутный болотный свет
	light.light_energy = 0.8
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/Rotmarsh.tscn")
	print("Rotmarsh generated!")
	quit()
