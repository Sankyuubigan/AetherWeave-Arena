extends SceneTree

## Q22: рендер-проба A/B/C в идентичных условиях (диагностика чёрных карточек C
## + сравнительные кадры). Запуск БЕЗ --headless.

const PREFABS := {
	"A": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage.tscn",
	"B": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v3_stock.tscn",
	"C": "res://Graphics/Environment/Props/spruce_mtree/spruce_mtree.tscn",
}

func _init() -> void:
	await process_frame
	await process_frame

	var holder := Node3D.new()
	root.add_child(holder)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	holder.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.6)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	holder.add_child(we)

	var cam := Camera3D.new()
	holder.add_child(cam)

	# Три дерева рядом: A x=-9, B x=0, C x=+9
	for pair in PREFABS:
		var prop = load(PREFABS[pair]).instantiate()
		prop.position = Vector3(-9 if pair == "A" else (0 if pair == "B" else 9), 0, 0)
		holder.add_child(prop)
	await process_frame

	DirAccess.make_dir_recursive_absolute("res://_tmp_probe/q22_abc/")
	cam.current = true

	# Общий план (все три)
	cam.position = Vector3(0, 9, 34)
	cam.look_at(Vector3(0, 7, 0))
	cam.current = true
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_abc/all_far.png")
	print("[PROBE] saved all_far.png")

	# Close кроны каждого
	var close := {
		"A": Vector3(-5.2, 6.0, 7.5),
		"B": Vector3(3.8, 6.0, 7.5),
		"C": Vector3(12.8, 6.0, 7.5),
	}
	for k in close:
		cam.position = close[k]
		cam.look_at(Vector3(-9 if k == "A" else (0 if k == "B" else 9), 7, 0))
		cam.current = true
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_abc/close_%s.png" % k)
		print("[PROBE] saved close_%s.png" % k)
	quit()
