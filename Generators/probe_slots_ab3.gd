extends SceneTree
## Проба слотов Q22 A+B v3: камера игрока перехватывала current — явный
## make_current() после каждого позиционирования.

func _init() -> void:
	await process_frame
	var arena := (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	for i in 12:
		await process_frame
	var q22 := arena.get_node_or_null("Q22TreeCompare")
	if q22 == null:
		printerr("[SLOTS] Q22TreeCompare NOT FOUND")
		quit(1)
		return
	var cam := Camera3D.new()
	q22.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(-3.0, 6.0, 16.0)
	cam.look_at(Vector3(-3.0, 8.0, -9.0))
	await _shot("slots_ab_far")
	cam.global_position = Vector3(-2.0, 5.0, 4.0)
	cam.look_at(Vector3(-3.0, 6.5, -9.0))
	cam.current = true
	await _shot("slots_ab_close")
	quit(0)

func _shot(nm: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://tasks/261117_2355-089dca89/q22_%s.png" % nm)
	print("[SLOTS] %s saved" % nm)
