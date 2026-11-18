extends SceneTree
## Визуальная проверка пилота MotionBricks Walk_Test (18.11.26): играем клип
## из shared_animations.res на player.tscn, камера следует за бёдрами,
## снимаем 9 кадров. Запуск: _tmp_probe/run_walk_check.ps1

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
	ap.play("Walk_Test")
	print("RW: Walk_Test length=", ap.get_animation("Walk_Test").length)

	var skel: Skeleton3D = null
	var stack: Array = [player]
	while stack:
		var nd = stack.pop_front()
		for c in nd.get_children():
			if c is Skeleton3D:
				skel = c
			stack.append(c)
	print("RW: скелет найден: ", skel != null)

	var times := [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5]
	for f in 9:
		ap.seek(times[f], f == 8)
		await process_frame
		await process_frame
		if skel:
			var bone_idx := skel.find_bone("mixamorig_Hips")
			var hip: Vector3 = skel.get_bone_global_pose(bone_idx).origin
			cam.position = hip + Vector3(1.2, 0.9, 2.4)
			cam.look_at(hip + Vector3(0, 0.15, 0))
		await _shot("walk_%02d_t%.1f.png" % [f, times[f]])
	print("RW: конец")
	quit(0)

func _shot(file_name: String) -> void:
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT + file_name)
	print("RW: кадр ", file_name)
