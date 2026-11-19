extends SceneTree
## Рендер-проба Q20 v9: перьевой веер с 4 РАКУРСОВ (вердикт юзера: «видны
## только с 1 ракурса — влево есть/вправо нет/вперёд одно»). Модель смотрит
## +Z → спина = −Z, левое крыло = +X. Паттерн probe_ragdoll_render: корутина,
## коллизионный пол, камера последняя. Детерминированная стат-поза (FPS 1 в
## пробах — фаза маха лотерейная, урок 19.11).

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
	e.background_color = Color(0.12, 0.14, 0.2)  # тёмный фон — ADD-крыло контрастно
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
	# FPS 1 в рендер-пробах: delta≈1с, LIFETIME истекает до снимка (урок 19.11)
	# и фаза маха лотерейная — замораживаем статикой.
	var comp = player.get_node_or_null("Wings")
	if comp:
		comp._life_left = 9999.0
		comp.set_process(false)
		comp._flap_phase = 0.0
		comp._sweep = 0.0
		# Детерминированный стат-поза: пивоты целых крыльев, перья в покое.
		comp._wing_l.rotation = Vector3(0.0, 0.3, 0.0)
		comp._wing_r.rotation = Vector3(0.0, -0.3, 0.0)
	for i in 25:
		await process_frame

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true

	# 4 ракурса: модель смотрит +Z. Спина=−Z, левое крыло=+X (side=1).
	var shots := [
		["back", Vector3(1.6, 2.2, -4.2), Vector3(0, 1.55, 0.3)],
		["left", Vector3(4.6, 1.9, -0.6), Vector3(0, 1.5, 0.0)],
		["right", Vector3(-4.6, 1.9, 0.6), Vector3(0, 1.5, 0.0)],
		["front", Vector3(-1.6, 2.0, 4.4), Vector3(0, 1.5, -0.2)],
	]
	for shot in shots:
		cam.position = shot[1]
		cam.look_at(shot[2])
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(
			"res://_tmp_probe/q_wings_v9_%s.png" % shot[0])
		print("[WP9] %s -> cam %s" % [shot[0], shot[1]])

	# Структура для лога: перья — внуки WingsRoot.
	var wroot = comp.get_parent().get_node_or_null("GraphicsWrapper/WingsRoot") \
		if comp else null
	if wroot:
		var n_mi := 0
		for c in wroot.get_children():
			for g in c.get_children():
				if g is MeshInstance3D:
					n_mi += 1
		print("[WP9] WingsRoot children=%d feathers=%d" % [wroot.get_child_count(), n_mi])

	# GLIDE-поза в воздухе (крылья назад): телепорт вверх + sweep глайда.
	if comp:
		comp._wing_l.rotation = Vector3(0.0, 1.2, 0.0)
		comp._wing_r.rotation = Vector3(0.0, -1.2, 0.0)
	for i in 20:
		player.global_position = Vector3(0, 3.0, 0)
		await process_frame
	cam.position = Vector3(1.6, 3.9, -4.4)
	cam.look_at(Vector3(0, 3.0, 0.3))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_wings_v9_glide.png")

	print("[WP9] PNG готовы")
	quit(0)
