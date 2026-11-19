extends SceneTree

## Рендер-проба Q22-C: префаб spruce_mtree (метод C, MTree) — 2 ракурса.
## Паттерн probe_arena_props_render (запуск БЕЗ --headless).

func _init() -> void:
	await process_frame
	await process_frame

	var holder := Node3D.new()
	root.add_child(holder)
	var prop = load("res://Graphics/Environment/Props/spruce_mtree/spruce_mtree.tscn").instantiate()
	holder.add_child(prop)
	await process_frame

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
	cam.current = true
	DirAccess.make_dir_recursive_absolute("res://_tmp_probe/spruce_mtree/")

	# Высота дерева ~14 м (MTree PINE trunk 14)
	var shots := [
		["far", Vector3(30, 0, 24), Vector3(0, 7, 0)],
		["close", Vector3(6, 3, 7), Vector3(0, 8, 0)],
	]
	for s in shots:
		cam.position = s[1]
		cam.look_at(s[2])
		cam.current = true
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://_tmp_probe/spruce_mtree/spruce_mtree_%s.png" % s[0])
		print("[PROBE] saved spruce_mtree_%s.png" % s[0])
	quit()
