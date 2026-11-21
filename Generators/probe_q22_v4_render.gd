extends SceneTree

## Q22-FIX/D: рендер-проба лайнапа v4 — A4 (конус+атлас A), B4 (конус+атлас B),
## C (MTree, эталон формы), D (C-скелет + A-атлас). Низкий ракурс — крона
## должна спускаться к земле (вердикт юзера: «А и Б висят в воздухе»).
## Запуск БЕЗ --headless (run_godot_render.ps1).

const PREFABS := {
	"A4": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_a.tscn",
	"B4": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_b.tscn",
	"C": "res://Graphics/Environment/Props/spruce_mtree/spruce_mtree.tscn",
	"D": "res://Graphics/Environment/Props/spruce_mtree_D/spruce_mtree_D.tscn",
}

func _init() -> void:
	var wd := create_timer(40.0)
	wd.timeout.connect(func() -> void:
		printerr("[Q22V4] TIMEOUT")
		quit(1))
	await process_frame
	await process_frame

	var holder := Node3D.new()
	root.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	holder.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.6)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	holder.add_child(we)
	# пол — контакт деревьев с землёй видно
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.42, 0.25)
	floor_mi.material_override = fmat
	holder.add_child(floor_mi)

	var cam := Camera3D.new()
	holder.add_child(cam)

	# 4 дерева с шагом 9 м: A4=-13.5, B4=-4.5, C=+4.5, D=+13.5
	var i := 0
	for k in PREFABS:
		var prop = load(PREFABS[k]).instantiate()
		prop.position = Vector3(-13.5 + 9.0 * i, 0, 0)
		holder.add_child(prop)
		i += 1
	await process_frame

	DirAccess.make_dir_recursive_absolute("res://_tmp_probe/q22_v4/")
	cam.current = true
	# общий план
	cam.position = Vector3(0, 8, 40)
	cam.look_at(Vector3(0, 7, 0))
	for f in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_v4/all_far.png")
	print("[Q22V4] saved all_far.png")
	# низкий ракурс: контакт кроны с землёй (главный чек фикса «висят»)
	cam.position = Vector3(0, 1.6, 26)
	cam.look_at(Vector3(0, 3.5, 0))
	for f in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_v4/all_low.png")
	print("[Q22V4] saved all_low.png")
	# close каждого
	var xs := {"A4": -13.5, "B4": -4.5, "C": 4.5, "D": 13.5}
	for k in xs:
		cam.position = Vector3(xs[k] + 4.0, 6.5, 10.0)
		cam.look_at(Vector3(xs[k], 6.0, 0))
		for f in 4:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_v4/close_%s.png" % k)
		print("[Q22V4] saved close_%s.png" % k)
	quit(0)
