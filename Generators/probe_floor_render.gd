extends SceneTree
## Рендер-проба пола (19.11.26, план «Пол — реалистичная поверхность»):
## снимки MainArena и ProceduralArena — вердикт по текстуре СВОИМИ ГЛАЗАМИ
## до доклада юзеру (правило: не заявлять фикс без картинки).
## Запуск (скрытое окно): powershell -File _tmp_probe/probe_floor_render.ps1

const OUT_DIR := "res://_tmp_probe/floor_check/"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _shot("res://Scenes/MainArena.tscn", "main_floor.png", Vector3(4, 5, 9), Vector3(0, 0, 0))
	await _shot("res://Scenes/ProceduralArena.tscn", "proc_floor.png", Vector3(3, 9, 12), Vector3(0, 1, 0))
	quit(0)

func _shot(scene_path: String, out_name: String, cam_pos: Vector3, look_at: Vector3) -> void:
	var arena: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(arena)
	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.global_position = cam_pos
	cam.look_at(look_at, Vector3.UP)
	cam.make_current()
	for i in 45:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + out_name))
	print("FR SHOT: %s %dx%d" % [out_name, img.get_width(), img.get_height()])
	arena.queue_free()
	await process_frame
	await process_frame
