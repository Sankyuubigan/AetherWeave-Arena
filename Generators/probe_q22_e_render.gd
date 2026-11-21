extends SceneTree

## Q22-E: рендер-проба дерева E (старая крона-облако + атлас B) рядом с B4
## (конус + атлас B) — один материал, разная форма: вердикт юзера по форме.
## Запуск БЕЗ --headless (run_window.ps1).

const B4 := "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_b.tscn"
const E := "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage_b.tscn"

func _init() -> void:
	var wd := create_timer(40.0)
	wd.timeout.connect(func() -> void:
		printerr("[Q22E] TIMEOUT")
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

	var b4 = load(B4).instantiate()
	b4.position = Vector3(-6, 0, 0)
	holder.add_child(b4)
	var e = load(E).instantiate()
	e.position = Vector3(6, 0, 0)
	holder.add_child(e)
	await process_frame

	DirAccess.make_dir_recursive_absolute("res://_tmp_probe/q22_e/")
	cam.current = true
	cam.position = Vector3(0, 8, 40)
	cam.look_at(Vector3(0, 7, 0))
	for f in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_e/far.png")
	print("[Q22E] saved far.png")
	cam.position = Vector3(6, 1.6, 14)
	cam.look_at(Vector3(6, 3.5, 0))
	for f in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_e/close_e.png")
	print("[Q22E] saved close_e.png")
	cam.position = Vector3(-6, 6.5, 12)
	cam.look_at(Vector3(-6, 6.0, 0))
	for f in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://_tmp_probe/q22_e/close_b4.png")
	print("[Q22E] saved close_b4.png")
	quit(0)
