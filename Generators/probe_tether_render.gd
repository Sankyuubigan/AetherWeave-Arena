extends SceneTree

## Q48 рендер-проба «Эфирного захвата» (паттерн probe_blade_render): скрытое
## окно --position -2400,-2400, три кадра: (1) burst+хлыст на зацепе,
## (2) зрелый жгут+шлейф в свинге, (3) отрыв — нить погасла, шлейф на падении.
## PNG: res://_tmp_probe/q_tether_*.png — смотреть глазами через Read.

func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://_tmp_probe")

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
	fbox.size = Vector3(60, 0.5, 60)
	fshape.shape = fbox
	floor_body.add_child(fshape)
	floor_body.position = Vector3(0, -0.25, 0)
	var fmi := MeshInstance3D.new()
	var fmesh := PlaneMesh.new()
	fmesh.size = Vector2(60, 60)
	fmi.mesh = fmesh
	floor_body.add_child(fmi)
	scene.add_child(floor_body)

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 25, 0)
	scene.add_child(player)
	await process_frame
	var hud = player.get_node_or_null("PlayerHUD")
	if hud:
		hud.visible = false

	var skills = load("res://Logic/Skills/SkillDB.gd").get_skills()
	var eff = null
	for e in skills["ether_tether"].effects:
		if e.get_script() != null \
				and e.get_script().resource_path.ends_with("TetherSwingEffect.gd"):
			eff = e
	var ctx_air := {
		"target_pos": Vector3(0, 12, -25),
		"hit_normal": Vector3.UP,
		"target_node": null,
		"camera_pos": Vector3(0, 25.6, 0),
		"forward_dir": Vector3(0, 0.3, -0.95).normalized(),
		"hand": "Left",
	}

	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.position = Vector3(5, 28, 9)
	cam.look_at(Vector3(0, 29, -8))
	cam.current = true

	# Кадр 1: burst + хлыст сразу после зацепа.
	eff.apply(player, ctx_air)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_tether_burst.png")
	print("PNG1 burst saved")

	# Кадр 2: зрелый жгут + шлейф в свинге.
	for i in 40:
		await physics_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_tether_swing.png")
	print("PNG2 swing saved")

	# Кадр 3: отрыв — нить погасла, тело летит по инерции со шлейфом.
	eff.apply(player, ctx_air)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_tether_release.png")
	print("PNG3 release saved")

	quit(0)
