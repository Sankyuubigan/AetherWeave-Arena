extends SceneTree
## Рендер-проба Q22-B: ель с CC0-фотосканом иголок (v3_stock) — far + close PNG.

func _init() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.5)
	world.add_child(env_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.1
	world.add_child(light)

	var tree := (load("res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v3_stock.tscn") as PackedScene).instantiate()
	world.add_child(tree)

	var cam := Camera3D.new()
	world.add_child(cam)
	for i in 10:
		await process_frame

	# AABB по визуальным потомкам (StaticBody3D.get_aabb не существует).
	var aabb: AABB = AABB()
	for mi in _find_mis(tree):
		aabb = aabb.merge(mi.get_aabb())
	print("[TREE-B] merged from %d MI" % _find_mis(tree).size())
	print("[TREE-B] aabb=", aabb)
	var center: Vector3 = aabb.get_center()
	# far: всё дерево
	cam.global_position = center + Vector3(9.0, 4.0, 9.0)
	cam.look_at(center)
	await _shot("tree_b_far")
	# close: крона крупно (читаемость карточек-иголок)
	var crown: Vector3 = center + Vector3(0, aabb.size.y * 0.25, 0)
	cam.global_position = crown + Vector3(3.0, 0.5, 3.0)
	cam.look_at(crown)
	await _shot("tree_b_close")
	quit(0)

func _find_mis(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_mis(c))
	return out

func _shot(nm: String) -> void:
	for i in 8:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://tasks/261117_2355-089dca89/q22_%s.png" % nm)
	print("[RENDER] %s saved" % nm)
