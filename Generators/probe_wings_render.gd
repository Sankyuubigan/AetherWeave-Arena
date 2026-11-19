extends SceneTree
## Рендер-проба Q20: крылья на спине игрока. PNG1 — FLAP на полу;
## PNG2 — GLIDE (телепорт вверх каждый кадр — держим airborne).
## Паттерн probe_ragdoll_render: корутина, коллизионный пол, камера ПОСЛЕДНЯЯ.

func _fskel(node: Node) -> Skeleton3D:
	if not node:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _fskel(c)
		if r:
			return r
	return null

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 0.5, 24)
	cs.shape = box
	floor_body.add_child(cs)
	var fmi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	fmi.mesh = plane
	floor_body.add_child(fmi)
	world.add_child(floor_body)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.14, 0.2)  # v6: тёмный фон — ADD-крыло видно контрастом
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.3, 0.36)
	env.environment = e
	world.add_child(env)

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.2, 0)
	world.add_child(player)
	await process_frame
	await process_frame
	var effect = load("res://Logic/Skills/SpawnWingsEffect.gd").new()
	effect.apply(player, {})
	# ГЛАВНАЯ ГРАБЛЯ Q20 (нашласть 19.11, FPS 1 в рендер-пробе): delta≈1с,
	# LIFETIME 10.0 истекает за ~10 кадров — deactivate() сжимает крылья
	# ДО снимка PNG1. Это и был весь «тупик» (v5/v7 ни при чём).
	var comp = player.get_node_or_null("Wings")
	if comp:
		comp._life_left = 9999.0
		# Детерминированная статика: FPS 1 двигает фазу маха на 3.4 рад/кадр —
		# каждый снимок был лотереей (маркеры и крыло в разных позах, 02:41).
		comp.set_process(false)
		comp._flap_phase = 0.0
		comp._sweep = 0.0
		comp._wing_l.rotation = Vector3(0.0, 0.55, 0.12)
		comp._wing_r.rotation = Vector3(0.0, -0.55, -0.12)
	for i in 25:
		await process_frame
	var cam := Camera3D.new()
	world.add_child(cam)
	# Вид на СПИНУ: модель смотрит +Z, камера сзади-сверху справа.
	cam.position = Vector3(2.4, 2.0, -3.6)
	cam.look_at(Vector3(0, 1.5, 0.4))
	cam.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_wings_flap.png")
	var wroot = player.get_node_or_null("Wings").get_node_or_null("WingsRoot")
	if wroot == null:
		var _sk = _fskel(player.get_node_or_null("GraphicsWrapper/PlayerModel"))
		wroot = _sk.get_node_or_null("SpineAttach/WingsRoot")
	var wl = null
	if wroot:
		for c in wroot.get_children():
			if c is MeshInstance3D:
				wl = c
				print("[RP] wroot global=", wroot.global_position,
					" scale=", wroot.scale)
				print("[RP] wroot basis x=", wroot.global_basis.x,
					" z=", wroot.global_basis.z)
		print("[RP] wing global=", wl.global_position if wl else null,
			" aabb=", wl.get_aabb() if wl else null)
		if wl and wl.mesh is ArrayMesh:
			var vv: PackedVector3Array = (wl.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			print("[RP] verts=", vv.size(), " v0=", vv[0], " vmax_x=", vv[0])
			var mx: float = vv[0].x
			for q in vv:
				if q.x > mx: mx = q.x
			print("[RP] max_x=", mx)

	# МАРКЕРЫ v6: красные шары по углам AABB крыла — где геометрия физически.
	var aabb: AABB = wl.get_aabb() if wl else AABB()
	if wroot and wl:
		for corner in [aabb.position,
			aabb.position + Vector3(aabb.size.x, 0, 0),
			aabb.position + Vector3(0, aabb.size.y, 0),
			aabb.position + aabb.size]:
			var mk := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.07
			sm.height = 0.14
			var mm := StandardMaterial3D.new()
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.albedo_color = Color(1, 0.1, 0.1)
			sm.material = mm
			mk.mesh = sm
			mk.global_position = wroot.to_global(corner)
			world.add_child(mk)
			print("[RP] corner ", corner, " -> ", mk.global_position)
	# КАМЕРА СТРОГО СО СПИНЫ (v6): мембрана с хордой вниз-назад видна сзади.
	cam.position = Vector3(0, 2.0, -4.6)
	cam.look_at(Vector3(0, 1.7, 0))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_wings_markers.png")

	# GLIDE: держим игрока в воздухе — телепорт каждый кадр.
	for i in 30:
		player.global_position = Vector3(0, 3.0, 0)
		await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_wings_glide.png")
	print("[WPROBE] PNG готовы")
	quit(0)
