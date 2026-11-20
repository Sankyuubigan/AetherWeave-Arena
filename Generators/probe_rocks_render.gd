extends SceneTree
## Q11 рендер-проба: живой ProceduralArena, камера на чанк группы камней.
## Проверка лично: 6 форм камней на террейне, врытие/масштаб/позиции ок.

var _frames := 0

func _init():
	# watchdog
	var t := create_timer(45.0)
	t.timeout.connect(func():
		printerr("ROCKS-RENDER TIMEOUT")
		quit(1)
	)
	_run()

func _run() -> void:
	var scene: PackedScene = load("res://Scenes/ProceduralArena.tscn")
	var arena = scene.instantiate()
	root.add_child(arena)
	# Q21-урок: current_scene для -s-проб назначать ЯВНО
	current_scene = arena

	# ждём генерацию (WFC/скаттер асинхронны) до появления 6 групп Rocks*
	var rocks_groups: Array[Node] = []
	for i in 900: # до 15 с
		await process_frame
		rocks_groups.clear()
		for g in ["Rocks", "Rocks_2", "Rocks_3", "Rocks_4", "Rocks_5", "Rocks_6"]:
			var n := arena.find_child(g, true, false)
			if n:
				rocks_groups.append(n)
		if rocks_groups.size() >= 6:
			break
	if rocks_groups.size() < 6:
		printerr("ROCKS-RENDER FAIL: нашлось групп %d/6" % rocks_groups.size())
		quit(1)
		return
	print("ROCKS-RENDER: групп %d/6, чанков у Rocks_3: %d" % [
		rocks_groups.size(),
		arena.find_child("Rocks_3", true, false).get_child_count()
	])

	# чанк группы Rocks_3 (rock_07) — камера на него
	var mmi: MultiMeshInstance3D = null
	for c in arena.find_child("Rocks_3", true, false).get_children():
		if c is MultiMeshInstance3D:
			mmi = c
			break
	if mmi == null:
		printerr("ROCKS-RENDER FAIL: у Rocks_3 нет MultiMesh-чанков")
		quit(1)
		return
	var aabb := mmi.get_aabb()
	var target: Vector3 = mmi.global_transform * aabb.get_center()
	print("ROCKS-RENDER: чанк центр %s" % target)

	# свет + небо-фон
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 30, 0)
	sun.light_energy = 1.1
	root.add_child(sun)

	# close: камера над чанком
	await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = target + Vector3(5, 6, 5)
	cam.look_at(target)
	cam.current = true
	for i in 12:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://_tmp_probe/prop_test/q11_scatter_close.png")
	print("ROCKS-RENDER: close PNG saved")

	# far: отъезд
	cam.position = target + Vector3(14, 10, 14)
	cam.look_at(target)
	for i in 12:
		await process_frame
	img = root.get_texture().get_image()
	img.save_png("res://_tmp_probe/prop_test/q11_scatter_far.png")
	print("ROCKS-RENDER: far PNG saved, GATE PASS")
	quit(0)
