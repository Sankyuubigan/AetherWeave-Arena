extends SceneTree

## Q47-F гейт-рендер: контракта подошвы — телепортер-арка (лифт из компонента
## снят, префаб нормализован), rock_moss (был низ -0.661, поднят), ряд Q22
## у края (костыль-цикл из билдера удалён). Запуск БЕЗ --headless.

const OUT := "res://_tmp_probe/q47_arena"

func _init() -> void:
	var wd := create_timer(90.0)
	wd.timeout.connect(func() -> void:
		printerr("[Q47F] TIMEOUT")
		quit(1))
	await process_frame
	await process_frame

	var arena: Node = (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await create_timer(1.5).timeout

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(OUT)

	# Телепортер-арка: низ префаба нормализован, компонент не лифтует
	cam.position = Vector3(32.3, 2.2, 32.3)
	cam.look_at(Vector3(38, 1.8, 38))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/q47f_tp.png")
	print("[Q47F] saved q47f_tp.png")
	# rock_moss (-5,0,-3) scale 0.8: был низ -0.661 → «врос»; теперь низ на полу
	cam.position = Vector3(-10.0, 3.0, 4.0)
	cam.look_at(Vector3(-5, 0.6, -3))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/q47f_rockmoss.png")
	print("[Q47F] saved q47f_rockmoss.png")
	# Ряд Q22 у края карты (q22_root (0,0,-45)): деревья растут из земли
	cam.position = Vector3(0, 5.0, -22.0)
	cam.look_at(Vector3(0, 2.0, -45))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/q47f_q22row.png")
	print("[Q47F] saved q47f_q22row.png")
	quit(0)
