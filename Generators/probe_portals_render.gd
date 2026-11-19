extends SceneTree
## Рендер-проба Q21: пара порталов на полу — A (синий, за спиной) и
## B (оранжевый, в точке прицела). PNG1 — общий план (оба кольца),
## PNG2 — крупный на выходное кольцо. Паттерн probe_wings_render:
## корутина, коллизионный пол, камера последняя.

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.5, 30)
	cs.shape = box
	floor_body.add_child(cs)
	var fmi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	fmi.mesh = plane
	floor_body.add_child(fmi)
	floor_body.position = Vector3(0, -0.25, 0)  # верх пола y=0 (как в гейт-тесте)
	world.add_child(floor_body)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.16)  # тёмный фон — эмиссив-кольца контрастны
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.3, 0.36)
	env.environment = e
	world.add_child(env)

	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 0.2, 0)
	world.add_child(player)
	current_scene = world  # -s-артефакт-фикс: pair должен быть в world, не в player
	for i in 10:
		await physics_frame  # физ-синхронизация пола до рейкастов эффекта
	print("[PP] player pos=", player.global_position)
	var effect = load("res://Logic/Skills/SpawnPortalsEffect.gd").new()
	# B в 7 м вперёд-вправо: fwd игрока +Z (без поворота), target_pos прицела.
	effect.apply(player, {"target_pos": Vector3(3, 0.2, 6)})

	# ДРЕЙФ-ЭКСПЕРИМЕНТ: контрольный голый Area3D + трасса y обоих порталов.
	var ctrl := Area3D.new()
	var ccs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(2.2, 2.6, 0.5)
	ccs.shape = cbox
	ctrl.add_child(ccs)
	root.add_child(ctrl)
	ctrl.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 2.0))
	var pair0 = player.get_meta("portal_pair")
	var pa0 = pair0.get_node("PortalA")
	var space = player.get_world_3d().direct_space_state  # player Variant — := нельзя
	for i in 12:
		await process_frame
		if i % 3 == 0:
			var rq := PhysicsRayQueryParameters3D.create(
				Vector3(0, 3, 0), Vector3(0, -3, 0))
			var rr = space.intersect_ray(rq)
			var floor_y: float = rr["position"].y if rr else -99.0
			print("[DRIFT] f=", i, " player=", player.global_position,
				" vel=", player.velocity, " on_floor=", player.is_on_floor(),
				" floor_y=", floor_y, " pair.y=", pair0.global_position.y)

	# FPS 1-4 в рендер-пробе: руны PortalRing крутятся в _process —
	# фаза на снимке лотерейная, но для колец это не ломает вид (не крылья).
	for i in 25:
		await process_frame

	var cam := Camera3D.new()
	world.add_child(cam)
	# Общий план: игрок + оба кольца (A за спиной ~z=-1.7, B на z=6).
	cam.position = Vector3(-5.5, 3.2, -6.5)
	cam.look_at(Vector3(1.5, 1.0, 2.0))
	cam.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_portals_pair.png")

	# Крупный: выходное кольцо B с фронтала (видна мембрана-вихрь + руны).
	cam.position = Vector3(3, 1.6, 9.2)
	cam.look_at(Vector3(3, 1.3, 6))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_portals_close.png")

	# Крупный: входное кольцо A за спиной игрока.
	cam.position = Vector3(0, 1.6, -4.8)
	cam.look_at(Vector3(0, 1.3, -1.7))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_portals_entry.png")

	var cur_cam := root.get_camera_3d()
	print("[PP] current cam=", cur_cam, " pos=",
		cur_cam.global_position if cur_cam else null)
	var pair = player.get_meta("portal_pair", null)
	if pair:
		for pn in ["PortalA", "PortalB"]:
			var p = pair.get_node_or_null(pn)
			if p:
				print("[PP]", pn, " pos=", p.global_position,
					" meshes=", _nm(p))
	print("[PPROBE] PNG готовы")
	quit(0)

func _nm(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			c += 1
	return c
