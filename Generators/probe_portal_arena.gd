extends SceneTree

## Q47 шаг 9: рендер-проба телепортера-арки в ЖИВЫХ аренах после замены капсулы.
## MainArena: телепортер (38,0,38) фронт к центру. HellArena: runtime-спавн (6,y,6).
## Урок probe_rocks_render: камера ПОСЛЕ арены, current явно. Запуск БЕЗ --headless.

const OUT := "res://_tmp_probe/q47_arena"

func _init() -> void:
	var wd := create_timer(90.0)
	wd.timeout.connect(func() -> void:
		printerr("[Q47A] TIMEOUT")
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
	# Фронт телепортера-арки (капсулы больше нет)
	cam.position = Vector3(32.3, 2.2, 32.3)
	cam.look_at(Vector3(38, 1.8, 38))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/tp_front.png")
	print("[Q47A] saved tp_front.png")
	# Подошва: контакт камня с полом (баг «провалились в пол» — проверка фикса
	# holder.position.y -= aabb.position.y*scale внутри компонента)
	cam.position = Vector3(33.5, 0.8, 40.5)
	cam.look_at(Vector3(38, 0.4, 37.5))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/tp_bases.png")
	print("[Q47A] saved tp_bases.png")
	# Сбоку: мембрана видна сквозь проём под углом (cull_disabled)
	cam.position = Vector3(40.5, 1.7, 33.0)
	cam.look_at(Vector3(38, 1.7, 38))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/tp_side.png")
	print("[Q47A] saved tp_side.png")
	arena.queue_free()
	await process_frame
	await process_frame

	# HellArena: телепортер runtime-спавн (6, _height(6,6)+0.1, 6)
	var hell: Node = (load("res://Scenes/HellArena.tscn") as PackedScene).instantiate()
	root.add_child(hell)
	await create_timer(1.5).timeout
	var tp: Node3D = hell.find_child("NPCTeleporter", true, false) as Node3D
	if tp == null:
		printerr("[Q47A] HellArena: NPCTeleporter не найден")
		quit(2)
		return
	var tp_pos := tp.global_position
	print("[Q47A] Hell телепортер на ", tp_pos)
	cam.position = tp_pos + Vector3(-4.0, 3.0, -4.0)
	cam.look_at(tp_pos + Vector3(0, 1.6, 0))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/tp_hell.png")
	print("[Q47A] saved tp_hell.png")
	cam.position = tp_pos + Vector3(0.0, 1.2, -5.0)
	cam.look_at(tp_pos + Vector3(0, 1.6, 0))
	for f in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "/tp_hell_front.png")
	print("[Q47A] saved tp_hell_front.png")
	quit(0)
