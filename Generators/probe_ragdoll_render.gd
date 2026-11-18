extends SceneTree

## Рендер-проба Q30 (вердикт юзера «рэгдоллов нигде нет, перс падает сквозь
## пол»): кукла-труп должна лежать НА МЕСТЕ СМЕРТИ, а не у origin. PNG смотрю
## сам: enemy_Demon в (2,0,-2) и player в (-2,1,0), убийство через activate,
## камера снаружи. PNG: _tmp_probe/q_ragdoll_fix.png

const RagdollScript = preload("res://Graphics/RagdollComponent.gd")

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame

	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.25, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
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

	# Враг ада со скином: смерть слева направо.
	var enemy = load("res://Scenes/enemy_Demon_T_Wiezzorek.tscn").instantiate()
	enemy.position = Vector3(2, 0.1, -2)
	scene.add_child(enemy)
	var erag := Node.new()
	erag.name = "Ragdoll"
	erag.set_script(RagdollScript)
	erag.set("tint", Color(0.55, 0.08, 0.06))
	enemy.add_child(erag)
	erag.activate(50, Vector3(1, 0, 0))

	# Игрок: смерть вверх (импульс юзера-смерти = (0,1,0)).
	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(-2, 1.0, 0)
	scene.add_child(player)
	await process_frame
	var prag = player.get_node_or_null("Ragdoll")
	if prag:
		prag.activate(100, Vector3(0, 1, 0))

	# Костям физике нужно время упасть и улечься.
	for i in 90:
		await process_frame

	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.position = Vector3(6, 3.2, 6)
	cam.look_at(Vector3(0, 0.8, -1))
	cam.current = true
	for i in 6:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("res://_tmp_probe/q_ragdoll_fix.png")
	print("RAGDOLL-RENDER DONE: enemy_doll=%d player_doll=%d" % [
		scene.get_children().filter(func(c): return c.name.begins_with("RagdollDummy")).size(),
		scene.get_children().filter(func(c): return c is Node3D and c.name.begins_with("RagdollDummy")).size(),
	])
	quit(0)
