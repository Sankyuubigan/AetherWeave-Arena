extends SceneTree
## Рендер-проба неба (мастер-план 18.11.26, задача 1): скриншот каждой карты
## на горизонте — проверить градиент/солнце/облака/эмберы. Запуск окном:
## powershell -File _tmp_probe/probe_sky.ps1

const MAPS := {
	"MainArena": {"frames": 40, "theme": "main"},
	"ProceduralArena": {"frames": 520, "theme": "forest"},
	"HellArena": {"frames": 520, "theme": "hell"},
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for map_name in MAPS:
		var cfg: Dictionary = MAPS[map_name]
		var scene: Node = (load("res://Scenes/%s.tscn" % map_name) as PackedScene).instantiate()
		root.add_child(scene)
		for i in int(cfg.frames):
			await process_frame
		var cam := Camera3D.new()
		scene.add_child(cam)
		cam.global_position = Vector3(0, 3.0, 14.0)
		cam.look_at(Vector3(0, 7.0, -30.0), Vector3.UP)  # лёгкий наклон вверх: небо + горизонт
		cam.make_current()
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "res://_tmp_probe/floor_check/sky_%s.png" % map_name
		img.save_png(ProjectSettings.globalize_path(path))
		print("SKYSHOT %s -> %s" % [map_name, path])
		root.remove_child(scene)
		scene.free()
	quit(0)
