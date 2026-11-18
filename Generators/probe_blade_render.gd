extends SceneTree

## Рендер-проба Q19: клинок в правой кисти (материализация + замах).
## Паттерн probe_ragdoll_render (проверен): корутина _init, камера последней,
## collision-пол. PNG: _tmp_probe/q_blade_idle.png, q_blade_swing.png

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
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
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

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.1, 0)
	scene.add_child(player)
	await process_frame

	var blade_comp = Node3D.new()
	blade_comp.name = "EnergyBlade"
	blade_comp.set_script(load("res://Graphics/EnergyBladeComponent.gd"))
	player.add_child(blade_comp)
	blade_comp.materialize()

	# Клинок вырос — снимок в позе idle.
	for i in 15:
		await process_frame

	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.position = Vector3(1.5, 1.7, 3.0)
	cam.look_at(Vector3(0, 1.3, 0))
	cam.current = true
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_blade_idle.png")
	print("PNG1 idle saved")

	# Замах: UB-свинговый оверлей поверх idle-ног.
	var anim_comp = player.get_node_or_null("PlayerAnimationComponent")
	if anim_comp and anim_comp.has_cast_anim("Blade_Swing_A"):
		anim_comp.play_cast_anim("Blade_Swing_A")
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_blade_swing.png")
	print("PNG2 swing saved")
	quit(0)
