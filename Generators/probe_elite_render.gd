extends SceneTree
## Рендер-проба Q38: скин Whiteclown N Hallin (элитный бот ада) — 2 ракурса PNG.

func _init() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.08, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	world.add_child(env_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.2
	world.add_child(light)

	var elite := (load("res://Scenes/enemy_Whiteclown_N_Hallin.tscn") as PackedScene).instantiate()
	world.add_child(elite)

	var cam := Camera3D.new()
	world.add_child(cam)

	var shots := [
		{"name": "front", "pos": Vector3(0, 1.5, 3.2)},
		{"name": "side", "pos": Vector3(3.0, 1.8, 2.2)},
	]
	for s in shots:
		elite.rotation_degrees.y = 0 if s.name == "front" else 90
		cam.global_position = s.pos
		cam.look_at(Vector3(0, 1.1, 0))
		for i in 8:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://tasks/261117_2355-089dca89/elite_render_%s.png" % s.name)
		print("[RENDER] %s saved" % s.name)
	quit(0)
