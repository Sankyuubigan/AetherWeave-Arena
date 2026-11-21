extends SceneTree

## Q22: рендер слотов A/E/B/C/D в ЖИВОЙ арене (после регена) + низкие ракурсы
## подошв (баг юзера 20.11.26 «деревья с земли, не в воздухе» — проверка контакта
## ствола с полом после опускания слотов за низ AABB).
## Запуск БЕЗ --headless (run_godot_render.ps1).

func _init() -> void:
	var wd := create_timer(60.0)
	wd.timeout.connect(func() -> void:
		printerr("[Q22SLOT] TIMEOUT")
		quit(1))
	await process_frame
	await process_frame

	var arena: Node = (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await create_timer(1.5).timeout

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true

	DirAccess.make_dir_recursive_absolute("res://_tmp_probe/q22_v4/")
	# Общий план ряда: A(0) E(-16) B(16) C(32) D(48), z=-45, ширина 64 м
	cam.position = Vector3(24, 9, -18)
	cam.look_at(Vector3(24, 7, -45))
	for f in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_v4/arena_slots.png")
	print("[Q22SLOT] saved arena_slots.png")
	# Подошвы A и E (низкий ракурс, чуть сбоку)
	cam.position = Vector3(8, 0.7, -38)
	cam.look_at(Vector3(-4, 0.5, -45))
	for f in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_v4/arena_bases_AE.png")
	print("[Q22SLOT] saved arena_bases_AE.png")
	# Подошвы B (справа от A) и C
	cam.position = Vector3(16, 0.7, -36)
	cam.look_at(Vector3(22, 0.5, -45))
	for f in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_v4/arena_bases_BC.png")
	print("[Q22SLOT] saved arena_bases_BC.png")
	quit(0)
