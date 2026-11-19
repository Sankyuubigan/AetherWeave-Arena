extends SceneTree
## Изо-проба v9.1: ГДЕ геометрия каждого пера. Маркеры-шары на кончиках
## перьев ОБЕИХ крыльев + печать global-AABB каждого меша. Урок v6: маркеры
## отделяют «меш не там» от «меш не рендерится».

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.14, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.35, 0.4)
	env.environment = e
	world.add_child(env)

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.2, 0)
	world.add_child(player)
	await process_frame
	await process_frame
	var effect = load("res://Logic/Skills/SpawnWingsEffect.gd").new()
	effect.apply(player, {})
	var comp = player.get_node_or_null("Wings")
	if comp:
		comp._life_left = 9999.0
		comp.set_process(false)
		comp._flap_phase = 0.0
		comp._sweep = 0.0
		comp._wing_l.rotation = Vector3(0.0, 0.3, 0.0)
		comp._wing_r.rotation = Vector3(0.0, -0.3, 0.0)
	for i in 20:
		await process_frame

	var gw = player.get_node_or_null("GraphicsWrapper")
	var wroot = gw.get_node_or_null("WingsRoot") if gw else null
	if wroot == null:
		print("[ISO] WingsRoot НЕ найден")
		quit(1)
		return
	print("[ISO] wroot pos=", wroot.global_position, " scale=", wroot.scale)
	var mk_i := 0
	for wing in wroot.get_children():
		if not (wing is Node3D):
			continue
		print("[ISO] wing pivot=", wing.name, " pos=", wing.global_position,
			" rot=", wing.rotation)
		for fp in wing.get_children():
			if not (fp is Node3D) or fp.get_child_count() == 0:
				continue
			var mi = fp.get_child(0)
			if not (mi is MeshInstance3D) or mi.mesh == null:
				print("[ISO]   перо без меша: ", fp.name)
				continue
			var arrs = mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
			var ab: AABB = mi.get_aabb()
			var t: Transform3D = mi.global_transform
			print("[ISO]   ", fp.name, " verts=", verts.size(),
				" rot_z=%.2f" % fp.rotation.z,
				" aabb_from=", t * ab.position,
				" aabb_to=", t * (ab.position + ab.size))
			# Маркер на глобальном кончике AABB (максимальный угол).
			var tip_local := Vector3(ab.position.x + ab.size.x,
				ab.position.y + ab.size.y, ab.position.z + ab.size.z)
			var mk := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			var mm := StandardMaterial3D.new()
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.albedo_color = Color(1, 0.15, 0.1)
			sm.material = mm
			mk.mesh = sm
			world.add_child(mk)
			mk.global_position = t * tip_local
			mk_i += 1

	print("[ISO] маркеров: ", mk_i)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(5.5, 3.2, 5.2)
	cam.look_at(Vector3(0, 2.0, 0))
	cam.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_wings_iso2.png")
	print("[ISO] PNG готов")
	quit(0)
