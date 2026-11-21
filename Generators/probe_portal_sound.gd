extends SceneTree
## Q47 шаг 7 гейт: эмбиент-аудио на месте в собранной арене (loop включён).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena: Node = (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await process_frame
	await process_frame
	var stand := arena.find_child("Q47PortalStand", true, false)
	var amb := stand.find_child("Ambient", true, false) if stand != null else null
	print("[Q47SND] stand=", stand != null, " ambient=", amb != null)
	var ok := stand != null and amb != null
	if ok and amb.stream != null:
		print("[Q47SND] loop_mode=", amb.stream.loop_mode, " loop_end=", amb.stream.loop_end, " autoplay=", amb.autoplay, " unit_size=", amb.unit_size)
		ok = amb.stream.loop_mode == 1 and amb.autoplay
	print("[Q47SND] ИТОГ: ", "OK" if ok else "ПРОВАЛ")
	quit(0 if ok else 1)
