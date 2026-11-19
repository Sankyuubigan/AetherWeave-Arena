extends SceneTree

## Рендер-проба Q37: нейро-пропы (стол зачарований + манекен) как префабы Godot.
## Паттерн probe_ragdoll_render: корутина _init, collision-пол, камера последней,
## PNG через root.get_texture(). Запуск БЕЗ --headless (dummy-рендерер даст чёрный PNG).

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame

	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.25, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.2
	scene.add_child(sun)

	var floor_body := StaticBody3D.new()
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(30, 0.5, 30)
	fshape.shape = fbox
	floor_body.add_child(fshape)
	floor_body.position = Vector3(0, -0.25, 0)
	var fmi := MeshInstance3D.new()
	var fmesh := PlaneMesh.new()
	fmesh.size = Vector2(30, 30)
	fmi.mesh = fmesh
	floor_body.add_child(fmi)
	scene.add_child(floor_body)

	var table = load("res://Graphics/Environment/Props/enchant_table/enchant_table.tscn").instantiate()
	table.position = Vector3(0, 0, 0)
	scene.add_child(table)
	var dummy = load("res://Graphics/Environment/Props/training_dummy/training_dummy.tscn").instantiate()
	dummy.position = Vector3(2.4, 0, -0.6)
	scene.add_child(dummy)
	await process_frame
	await process_frame

	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	var out := "res://_tmp_probe/neuro_props/"

	# 1) стол крупно (3/4 сверху)
	cam.position = Vector3(1.6, 1.3, 1.7)
	cam.look_at(Vector3(0, 0.45, 0))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "prefab_table.png")
	print("PNG1 table saved")

	# 2) манекен крупно
	cam.position = Vector3(1.5, 1.2, 1.4)
	cam.look_at(Vector3(2.4, 0.55, -0.6))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "prefab_dummy.png")
	print("PNG2 dummy saved")

	# 3) оба в кадре (масштабный контекст)
	cam.position = Vector3(3.6, 1.7, 4.2)
	cam.look_at(Vector3(1.2, 0.5, -0.3))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "prefab_both.png")
	print("PNG3 both saved")
	quit(0)
