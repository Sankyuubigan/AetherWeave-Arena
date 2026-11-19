extends SceneTree
## Проба слотов Q22 A+B+C после правки юзера: деревья на краю карты (z=-170),
## шаг 20/40 м, лейблы font 96. Один запуск.

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
	print("[SLOTS] root at: ", q22.global_position)
	for nm in ["TreeA_AtlasCards", "TreeB_StockScanCards", "TreeC_MTree"]:
		var t := q22.get_node_or_null(nm)
		print("[SLOTS] %s: %s" % [nm, "OK" if t != null else "MISSING"])
	var cam := Camera3D.new()
	q22.add_child(cam)
	cam.global_position = Vector3(20, 7.0, -150)
	cam.look_at(Vector3(20, 8.0, -170))
	cam.current = true
	await _shot("slots_abc_edge_far")
	cam.global_position = Vector3(13.0, 4.5, -162)
	cam.look_at(Vector3(20, 7.0, -170))
	cam.current = true
	await _shot("slots_abc_edge_close")
	quit(0)

func _shot(nm: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://tasks/261117_2355-089dca89/q22_%s.png" % nm)
	print("[SLOTS] %s saved" % nm)
