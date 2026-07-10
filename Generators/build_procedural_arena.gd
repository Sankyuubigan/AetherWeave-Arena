extends SceneTree

# Теперь этот генератор создает только ПУСТУЮ сцену с прикрепленным скриптом, 
# который сгенерирует карту в момент запуска игры. Это решает проблему 1МБ файла.

func _init():
	var root = Node3D.new()
	root.name = "ProceduralArena"

	# Добавляем свет и небо, чтобы было красиво
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

	# Прикрепляем скрипт РЕАЛЬНОГО ВРЕМЕНИ
	root.set_script(load("res://Logic/Procedural/ProceduralArena.gd"))

	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://Scenes/ProceduralArena.tscn")
	print("ProceduralArena wrapper generated! Actual generation will happen at runtime.")
	quit()