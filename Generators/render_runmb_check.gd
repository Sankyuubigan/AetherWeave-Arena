extends SceneTree
## Визуальная проверка ШВА ЛУПА Run_MB (18.11.26, раунд 23в): кадры у стыка
## (хвост 1.35–1.56 с) против головы (0.0–0.12 с) — шов должен быть непрерывным.
## Запуск: _tmp_probe/run_runmb_check.ps1

const OUT := "res://_tmp_probe/"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(60, 1, 60)
	floor_mesh.mesh = mesh
	floor_body.add_child(floor_mesh)
	world.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	world.add_child(sun)
	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.0, 0)
	world.add_child(player)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true

	var comp = player.get_node("PlayerAnimationComponent")
	for i in 100:
		await process_frame

	var ap: AnimationPlayer = comp.anim_player
	# Точная поза в снимке: замираем время (при FPS 2 между seek и кадром
	# проходит ~1 с реального времени — playback уезжал) и глушим стейт-машину
	# (иначе AnimationTree перебивает ручной seek своей текущей позой).
	ap.speed_scale = 0.0
	for nd in player.find_children("*", "AnimationTree", true, false):
		nd.active = false
	ap.play("Run_MB")
	print("RW: Run_MB length=", ap.get_animation("Run_MB").length, " loop=", ap.get_animation("Run_MB").loop_mode)

	var skel: Skeleton3D = null
	var stack: Array = [player]
	while stack:
		var nd = stack.pop_front()
		for c in nd.get_children():
			if c is Skeleton3D:
				skel = c
			stack.append(c)
	print("RW: скелет найден: ", skel != null)

	# Кадры у шва — ДОЛИ длины клипа (луп теперь короткий ~0.35–0.5 с):
	# голова (0–10%), середина, хвост (82–100%).
	var L: float = ap.get_animation("Run_MB").length
	var fracs := [0.0, 0.03, 0.1, 0.4, 0.82, 0.9, 0.95, 0.98, 1.0]
	for f in fracs.size():
		var t: float = fracs[f] * L
		ap.seek(t, f == fracs.size() - 1)
		await process_frame
		await process_frame
		if skel:
			var bone_idx := skel.find_bone("mixamorig_Hips")
			var hip: Vector3 = skel.get_bone_global_pose(bone_idx).origin
			cam.position = hip + Vector3(1.2, 0.9, 2.4)
			cam.look_at(hip + Vector3(0, 0.15, 0))
		await _shot("runmb_%02d_t%.2f.png" % [f, t])
	print("RW: конец")
	quit(0)

func _shot(file_name: String) -> void:
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT + file_name)
	print("RW: кадр ", file_name)
