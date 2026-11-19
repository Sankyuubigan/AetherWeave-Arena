extends SceneTree
## Контроль посадки деревьев на грунт у края карты (z=-170): взгляд вдоль земли.

func _init() -> void:
	await process_frame
	var arena := (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	for i in 12:
		await process_frame
	var q22 := arena.get_node_or_null("Q22TreeCompare")
	if q22 == null:
		quit(1)
		return
	var cam := Camera3D.new()
	q22.add_child(cam)
	cam.global_position = Vector3(20, 1.2, -34)
	cam.look_at(Vector3(20, 1.5, -47))
	cam.current = true
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://tasks/261117_2355-089dca89/q22_ground_check.png")
	print("[SLOTS] ground check saved")
	quit(0)
