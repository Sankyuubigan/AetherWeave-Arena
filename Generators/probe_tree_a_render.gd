extends SceneTree
## Рендер-проба Q22 метод A (процедурный атлас хвои): ель-v2 с 3 ракурсов.
## far = силуэт целиком, close = карточки крупно (атлас/иголки),
## up = снизу вверх (чек cull DISABLED — карточки двусторонние).

const OUT := "res://tasks/261117_2355-089dca89/"

func _init() -> void:
	await process_frame
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.5, 40)
	cs.shape = box
	floor_body.add_child(cs)
	var fmi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	fmi.mesh = plane
	floor_body.add_child(fmi)
	world.add_child(floor_body)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.light_energy = 1.2
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.62, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.5)
	env.environment = e
	world.add_child(env)

	var tree = load("res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage.tscn").instantiate()
	world.add_child(tree)
	await process_frame
	await process_frame

	var mi_list: Array = []
	_collect(tree, mi_list)
	for mi in mi_list:
		for s in mi.mesh.get_surface_count():
			var mat = mi.mesh.surface_get_material(s)
			if mat:
				print("MAT %s surf %d: %s transp=%d cull=%d"
					% [mi.name, s, mat.resource_name,
					int(mat.transparency), int(mat.cull_mode)])

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var shots := [
		[Vector3(20, 10, 20), Vector3(0, 6.5, 0), "far"],
		[Vector3(4.5, 9.5, 4.5), Vector3(0, 9.5, 0), "close"],
		[Vector3(3.0, 1.7, 3.0), Vector3(0, 9.0, 0), "up"],
	]
	for sh in shots:
		cam.position = sh[0]
		cam.look_at(sh[1])
		await process_frame
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OUT + "q22_tree_a_%s.png" % sh[2])
		print("SHOT %s saved" % sh[2])
	quit(0)

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
