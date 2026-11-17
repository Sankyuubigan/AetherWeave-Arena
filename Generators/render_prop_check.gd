extends SceneTree
## Кадровая проверка нейро-пропа: test_stone.tscn на сером фоне, 2 ракурса.
## Запуск (скрытое окно): _tmp_probe/run_prop_check.ps1
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.4, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.0
	root.add_child(sun)
	var prop = load("res://Graphics/Environment/Props/test_stone/test_stone.tscn").instantiate()
	root.add_child(prop)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(2.4, 1.7, 2.8)
	cam.look_at(Vector3(0, 0.45, 0))
	cam.current = true
	for i in 30:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/prop_test/stone_prefab_a.png")
	print("RP: кадр A")
	cam.position = Vector3(-2.6, 1.2, 1.8)
	cam.look_at(Vector3(0, 0.45, 0))
	for i in 10:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/prop_test/stone_prefab_b.png")
	print("RP: кадр B")
	quit(0)
