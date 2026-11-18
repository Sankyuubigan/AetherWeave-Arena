extends SceneTree
## Зонд шва рельефа (19.11.26, план «Швы рельефа ProceduralArena»): снимок стыка
## чанков у линии x=0 (внутренние плотные чанки, res 24 = 24). Камера ставится
## рейкастом вниз, чтобы не утонуть в рельефе (высота шума ±4 м).
## Запуск: powershell -File _tmp_probe/probe_terrain_seam.ps1 <метка_файла>

var tag := "before"

func _init() -> void:
	var args := OS.get_cmdline_args()
	for a in args:
		if not a.begins_with("-") and not a.ends_with(".gd") and not a.begins_with("res:"):
			tag = a.strip_edges()
	call_deferred("_run")

func _run() -> void:
	var arena: Node = (load("res://Scenes/ProceduralArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	for i in 20:
		await physics_frame
	for i in 30:
		await process_frame
	# Рейкаст вне WFC-лагеря, у границы плотный/разреженный LOD (линия x=50,
	# рядом пересечение с z=-50): hit.collider должен быть Terrain.
	var space := root.get_world_3d().direct_space_state
	var from := Vector3(55.0, 30.0, -65.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("TS РЕЙКАСТ ПУСТ — камера вслепую")
	var gy: float = hit["position"].y if hit.has("position") else 2.0
	if hit.has("collider"):
		print("TS collider=%s" % (hit["collider"] as Node).name)
	var cam := Camera3D.new()
	arena.add_child(cam)
	# Крупный план: взгляд поперёк линии стыка x=50
	cam.global_position = Vector3(57.0, gy + 2.4, -63.0)
	cam.look_at(Vector3(48.0, gy - 0.8, -72.0), Vector3.UP)
	cam.make_current()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := "res://_tmp_probe/floor_check/seam_%s.png" % tag
	img.save_png(ProjectSettings.globalize_path(out))
	print("TS SHOT: %s (ground_y=%.2f)" % [out, gy])
	# Общий план: несколько стыков сразу (x=50 и x=0 в глубине)
	var cam2 := Camera3D.new()
	arena.add_child(cam2)
	cam2.global_position = Vector3(70.0, gy + 9.0, -55.0)
	cam2.look_at(Vector3(20.0, gy - 2.0, -95.0), Vector3.UP)
	cam2.make_current()
	await RenderingServer.frame_post_draw
	var img2 := root.get_texture().get_image()
	var out2 := "res://_tmp_probe/floor_check/seam_%s_wide.png" % tag
	img2.save_png(ProjectSettings.globalize_path(out2))
	print("TS SHOT: %s" % out2)
	quit(0)
