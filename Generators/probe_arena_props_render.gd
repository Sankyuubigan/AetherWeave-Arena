extends SceneTree

## Рендер-проба Q37 в КОНТЕКСТЕ арены: манекены (стоячие) + стол зачарований.
## Паттерн probe_ragdoll_render. Запуск БЕЗ --headless.

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame

	var arena = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	await process_frame

	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.current = true
	var out := "res://_tmp_probe/neuro_props/"

	# 1) вражеский стоячий манекен (0,1,-5) — нейро-проп на месте капсулы
	cam.position = Vector3(1.8, 1.8, -2.0)
	cam.look_at(Vector3(0, 1.0, -5))
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "arena_dummy.png")
	print("PNG1 arena dummy saved")

	# 2) стол зачарований (35.5,0,35.5) у непись-телепортера (угол карты)
	cam.position = Vector3(33.2, 1.9, 33.2)
	cam.look_at(Vector3(35.6, 0.8, 35.6))
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "arena_table.png")
	print("PNG2 arena table saved")

	# 3) стол + циановый телепортер (38,0,38) — контекст угла карты
	cam.position = Vector3(32.5, 2.6, 31.5)
	cam.look_at(Vector3(36.2, 1.0, 37.2))
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "arena_both.png")
	print("PNG3 arena both saved")
	quit(0)
