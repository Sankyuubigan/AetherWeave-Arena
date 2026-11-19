extends SceneTree
## Рендер-проба Q22: слоты сравнения деревьев у спавна в живой арене
## (MainArena целиком, как увидит юзер). PNG1 общий, PNG2 ближе.

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame
	var arena = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(arena)
	for i in 30:
		await process_frame
	var q22 = arena.get_node_or_null("Q22TreeCompare")
	print("[Q22] slots node: ", q22)
	if q22 == null:
		quit(1)
		return
	print("[Q22] tree at ", (q22.get_node_or_null("TreeA_AtlasCards") as Node3D).global_position)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var shots := [
		[Vector3(-1.0, 2.2, -3.0), Vector3(-6.5, 8.0, -9.0), "wide"],
		[Vector3(-2.5, 3.0, -5.5), Vector3(-5.0, 7.5, -9.0), "mid"],
	]
	for sh in shots:
		cam.position = sh[0]
		cam.look_at(sh[1])
		for i in 12:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://tasks/261117_2355-089dca89/q22_slots_%s.png" % sh[2])
		print("SHOT %s saved" % sh[2])
	quit(0)
