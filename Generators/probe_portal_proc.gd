extends SceneTree

## Q47 шаг 9 (добивка юзера 21.11.26 «на Процедурной арена телепортер должен быть»):
## рендер-проба арки-телепортера на процедурной арене — пол неровный (heightmap),
## проверка посадки (не висит / не провалена). Запуск БЕЗ --headless.

const OUT := "res://_tmp_probe/q47_arena"

func _init() -> void:
	var wd := create_timer(120.0)
	wd.timeout.connect(func() -> void:
		printerr("[Q47P] TIMEOUT")
		quit(1))
	await process_frame
	await process_frame

	var arena: Node = (load("res://Scenes/ProceduralArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	# Рантайм-генерация WFC+скаттер с loading overlay — ждём подольше
	await create_timer(5.0).timeout

	var tp: Node3D = arena.find_child("NPCTeleporter", true, false) as Node3D
	if tp == null:
		printerr("[Q47P] NPCTeleporter не найден на ProceduralArena")
		quit(2)
		return
	# Арка должна быть внутри (PortalArch спавнится в _ready телепортера)
	var arch: Node = tp.find_child("PortalArch", true, false)
	print("[Q47P] tp на ", tp.global_position, "; PortalArch=", arch != null)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(OUT)

	var tp_pos := tp.global_position
	# Фронт: арка видна целиком вместе с контактом камня и рельефа
	cam.position = tp_pos + Vector3(-5.0, 3.0, -6.0)
	cam.look_at(tp_pos + Vector3(0, 1.6, 0))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/tp_proc.png")
	print("[Q47P] saved tp_proc.png")
	# Подошва крупно
	cam.position = tp_pos + Vector3(-2.0, 0.9, -4.0)
	cam.look_at(tp_pos + Vector3(0, 0.5, 0))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/tp_proc_base.png")
	print("[Q47P] saved tp_proc_base.png")
	quit(0)
