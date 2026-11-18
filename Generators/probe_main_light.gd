extends SceneTree
## Скриншот-проба света MainArena (19.11.26): темнее/контрастнее — VFX-сферы
## должны читаться ярче. Headless НЕ рендерит — запуск через скрытое окно.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var s = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(s)
	for i in 10:
		await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(16, 7, 16)
	cam.look_at(Vector3(0, 1.2, 0))
	cam.current = true
	for i in 8:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://_tmp_probe/floor_check/main_light_after.png")
	print("PROBE light screenshot saved")
	quit()
