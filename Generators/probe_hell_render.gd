extends SceneTree
## Зонд ада (19.11.26, план «Ад»): ждём генерацию, снимаем общий план + крупный
## (лава/шпили/враги/непись). Запуск: powershell -File _tmp_probe/probe_hell.ps1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena: Node = (load("res://Scenes/HellArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	# Генерация по шагам (оверлей) — ждём несколько секунд кадров.
	for i in 420:
		await process_frame
	# Факт-чек: непись, враги, лава, рельеф.
	var npc := arena.get_node_or_null("NPCTeleporter")
	var melee := 0
	var ranged := 0
	for c in arena.get_children():
		if String(c.name).begins_with("Melee_"): melee += 1
		if String(c.name).begins_with("Ranged_"): ranged += 1
	print("HE npc=%s melee=%d ranged=%d lava=%s terrain=%s" % [
		str(npc != null), melee, ranged,
		str(arena.get_node_or_null("Lava") != null),
		str(arena.get_node_or_null("Terrain") != null)])
	# Камера: общий план от точки спавна.
	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.global_position = Vector3(0, 6, 14)
	cam.look_at(Vector3(0, 2, 0), Vector3.UP)
	cam.make_current()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_tmp_probe/floor_check/hell_wide.png"))
	print("HE SHOT hell_wide.png")
	# Крупный: непись у спавна + враги в кадре.
	var cam2 := Camera3D.new()
	arena.add_child(cam2)
	cam2.global_position = Vector3(10, 3.5, 10)
	cam2.look_at(Vector3(4, 1.5, 5), Vector3.UP)
	cam2.make_current()
	await RenderingServer.frame_post_draw
	var img2 := root.get_texture().get_image()
	img2.save_png(ProjectSettings.globalize_path("res://_tmp_probe/floor_check/hell_close.png"))
	print("HE SHOT hell_close.png")
	quit(0)
