extends SceneTree
## Различительный зонд шейдинга: prop_shading_test <prop> <variant>
## flat    — все поверхности перекрашены белым без текстур (чистая геометрия)
## nonormal— родные материалы, но normal_enabled=false (вина нормал-мапа?)
## full    — без изменений (базлайн)
## Кадр в _tmp_probe/prop_test/<prop>_shade_<variant>.png. Скрытое окно, НЕ --headless.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prop_name: String = args[0] if args.size() > 0 else "rock_moss_set_01"
	var variant: String = args[1] if args.size() > 1 else "flat"
	var prop_path := "res://Graphics/Environment/Props/%s/%s.tscn" % [prop_name, prop_name]
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
	var white_mat: StandardMaterial3D = StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.8, 0.8, 0.8)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = center + Vector3(radius * 1.4, radius * 0.9, radius * 1.6)
	cam.look_at(center)
	cam.current = true
	for i in 20:
		await process_frame
	for mi in _all_mesh_instances(prop):
		match variant:
			"flat":
				mi.material_override = white_mat
			"nonormal":
				for s in mi.mesh.get_surface_count():
					var m: Material = mi.mesh.surface_get_material(s)
					if m is BaseMaterial3D:
						var dup: BaseMaterial3D = (m as BaseMaterial3D).duplicate()
						dup.normal_enabled = false
						mi.set_surface_override_material(s, dup)
			"noorm":
				for s in mi.mesh.get_surface_count():
					var m2: Material = mi.mesh.surface_get_material(s)
					if m2 is ORMMaterial3D:
						var d2: ORMMaterial3D = (m2 as ORMMaterial3D).duplicate()
						d2.orm_texture = null
						d2.ao_enabled = false
						d2.metallic = 0.0
						d2.roughness = 0.9
						mi.set_surface_override_material(s, d2)
	# Материал применяется к СЛЕДУЮЩЕМУ кадру — без ожидания снят старый.
	for i in 5:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/prop_test/%s_shade_%s.png" % [prop_name, variant])
	print("ST: %s %s готово" % [prop_name, variant])
	quit(0)

func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	var st: Array = [node]
	while st:
		var nd = st.pop_front()
		if nd is MeshInstance3D:
			out.append(nd)
		for c in nd.get_children():
			st.append(c)
	return out
