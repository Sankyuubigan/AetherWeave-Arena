extends SceneTree
## Рендер-проба шага 5 Q47: PortalArchVisual A (готика) и B (кольцо) с мембраной.
## Скрытое окно (не --headless: null viewport, кадр не снимается). PNG в _tmp_probe/prop_test/.
## Запуск: powershell -File _tmp_probe/probe_portal_arch.ps1

const DIR := "res://_tmp_probe/prop_test"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.22, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	root.add_child(sun)

	var vis_script := load("res://Graphics/PortalArchVisual.gd")
	var a = vis_script.new()
	a.name = "ArchA"
	a.arch_prefab = load("res://Graphics/Environment/Props/portal_arch_a/portal_arch_a.tscn")
	a.mask_type = 1
	a.membrane_size_frac = Vector2(0.72, 0.84)
	a.membrane_center_frac = Vector2(0.5, 0.43)
	a.seed_off = 0.0
	a.position = Vector3(-1.9, 0, 0)
	root.add_child(a)
	var b = vis_script.new()
	b.name = "ArchB"
	b.arch_prefab = load("res://Graphics/Environment/Props/portal_arch_b/portal_arch_b.tscn")
	b.mask_type = 0
	b.membrane_size_frac = Vector2(0.67, 0.67)
	b.membrane_center_frac = Vector2(0.5, 0.48)
	b.seed_off = 3.7
	b.position = Vector3(1.9, 0, 0)
	root.add_child(b)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.7, 4.8)
	cam.current = true
	cam.look_at(Vector3(0, 1.5, 0))
	for i in 40:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(DIR + "/portal_arch_visual_a.png")
	print("PA: кадр A")
	cam.position = Vector3(3.4, 1.0, 3.8)
	cam.look_at(Vector3(0, 1.4, 0))
	for i in 10:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	img.save_png(DIR + "/portal_arch_visual_b.png")
	print("PA: кадр B")

	# Кадр C: LOW-фолбэк — заглушка GraphicsQuality (quality=0) до добавления арки.
	var stub := Node.new()
	stub.name = "GraphicsQuality"
	stub.set_script(load("res://Generators/probe_quality_stub.gd"))
	root.add_child(stub)
	var c = vis_script.new()
	c.name = "ArchA_LOW"
	c.arch_prefab = load("res://Graphics/Environment/Props/portal_arch_a/portal_arch_a.tscn")
	c.mask_type = 1
	c.membrane_size_frac = Vector2(0.72, 0.84)
	c.membrane_center_frac = Vector2(0.5, 0.43)
	c.position = Vector3(5.8, 0, 0)
	root.add_child(c)
	cam.position = Vector3(5.8, 1.6, 4.4)
	cam.look_at(Vector3(5.8, 1.4, 0))
	for i in 20:
		await process_frame
	img = root.get_viewport().get_texture().get_image()
	img.save_png(DIR + "/portal_arch_visual_low.png")
	print("PA: кадр C (LOW)")
	quit(0)
