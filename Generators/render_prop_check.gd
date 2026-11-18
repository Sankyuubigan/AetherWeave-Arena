extends SceneTree
## Кадровая проверка пропа: Props/<имя>/<имя>.tscn на сером фоне, 2 ракурса.
## Камера сама отъезжает на габарит пропа (AABB), PNG в _tmp_probe/prop_test/.
## Запуск (скрытое окно): powershell -File _tmp_probe/render_prop_check.ps1 -prop <имя>
## (--headless не годится: null viewport, кадр не снимается)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prop_name: String = args[0] if args.size() > 0 else "test_stone"
	var prop_path := "res://Graphics/Environment/Props/%s/%s.tscn" % [prop_name, prop_name]
	if not ResourceLoader.exists(prop_path):
		print("RP: НЕТ ПРЕФАБА ", prop_path)
		quit(1)
		return
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
	var prop: Node3D = load(prop_path).instantiate()
	root.add_child(prop)
	# Габарит по объединённому AABB визуальных детей (origin бывает не в подошве)
	var aabb := AABB()
	var first := true
	var stack: Array = [prop]
	while stack:
		var nd = stack.pop_front()
		if nd is VisualInstance3D:
			var ta: AABB = prop.global_transform.affine_inverse() * nd.global_transform * nd.get_aabb()
			aabb = ta if first else aabb.merge(ta)
			first = false
		for c in nd.get_children():
			stack.append(c)
	var center := aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 0.5)
	print("RP: %s AABB %s, r=%.2f" % [prop_name, aabb, radius])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = center + Vector3(radius * 1.4, radius * 0.9, radius * 1.6)
	cam.look_at(center)
	cam.current = true
	for i in 30:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/prop_test/%s_check_a.png" % prop_name)
	print("RP: кадр A")
	cam.position = center + Vector3(-radius * 1.5, radius * 0.6, radius * 1.1)
	cam.look_at(center)
	for i in 10:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/prop_test/%s_check_b.png" % prop_name)
	print("RP: кадр B")
	quit(0)
