extends SceneTree
## Кадровая проверка AnimationTree (17.11.26): РЕАЛЬНЫЙ компонент (скрипты живы,
## дерево строит он сам), игрок стоит на полу. Сценарий: Idle через дерево →
## travel Run → UB-каст поверх бега → перебивание другим кастом (спам-фикс).
## Запуск (скрытое окно, §11.29): _tmp_probe/run_tree_check.ps1

const OUT := "res://_tmp_probe/"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Мир: пол, свет, камера
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(30, 1, 30)
	floor_mesh.mesh = mesh
	floor_body.add_child(floor_mesh)
	world.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	world.add_child(sun)

	# Игрок СО СКРИПТАМИ (компонент строит дерево в _ready)
	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 1.0, 0)
	world.add_child(player)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0.4, 1.7, 3.0)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true

	var comp = player.get_node("PlayerAnimationComponent")
	# Оседание на пол; дерево стартует Idle само
	for i in 90:
		await process_frame
	print("RT: локомоция после оседания = ", comp.loco_state())
	await _shot("tree_00_idle.png")

	# Run через дерево (FSM компонента спим: скорости нет, иначе вернёт Idle)
	comp.set_process(false)
	comp._travel("Run")
	await process_frame
	for i in 50:
		await process_frame
	print("RT: после travel(Run) дерево = ", comp.playback.get_current_node())
	await _shot("tree_10_run_a.png")
	for i in 20:
		await process_frame
	await _shot("tree_11_run_b.png")

	# UB-каст поверх бега (дерево продолжает вести ноги)
	comp.play_cast_anim("Heart_Cast")
	for i in 8:
		await process_frame
	await _shot("tree_20_heart_start.png")
	for i in 14:
		await process_frame
	await _shot("tree_21_heart_mid.png")

	# Спам: перебивание другим кастом — рестарт с нуля (фикс раунда 14)
	comp.play_cast_anim("Throw")
	for i in 10:
		await process_frame
	await _shot("tree_30_throw_a.png")
	for i in 15:
		await process_frame
	await _shot("tree_31_throw_b.png")

	print("RT DONE, касты = ", comp.cast_player.current_animation)
	quit(0)

func _shot(file_name: String) -> void:
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT + file_name)
	print("RT: кадр ", file_name)
