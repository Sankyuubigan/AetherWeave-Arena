extends SceneTree
## Рендер-проба Q44: «живое окно» портала v2 (НЕ headless, общий World3D).
## front — мембрана A анфас: в окне маркер B-стороны (жёлтый куб B-SIDE);
## angle — косой взгляд: вихрь-край + картинка в центре; back — мембрана B
## с её стороны: окно B показывает камерную сторону (красный куб).
## close — вплотную (d=1.2 м): flat-«дырка» без марева, 768×432;
## parallaxL/R — один и тот же портал с ЛЕВОГО и ПРАВОГО ракурса: жёлтый
## куб в окне должен СЪЕХАТЬ в разные стороны (параллакс-камера, репорт
## юзера 20.11.26 «картинка не меняется от угла обзора»).
## open_ms — build+bind до первых кадров окна (цель <50, нет фриза).

var open_ms := 0

func _shot(cam: Camera3D, pos: Vector3, to: Vector3, path: String) -> void:
	cam.global_position = pos
	cam.look_at(to)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _init() -> void:
	await process_frame
	# Компиляция скриптов ВНЕ замера (в живой игре компилируются на старте;
	# open_ms меряет только стоимость build+bind окна).
	var _pre1 = load("res://Logic/PortalNode2.gd")
	var _pre2 = load("res://Graphics/PortalRing2.gd")
	var _pre3 = load("res://Logic/Skills/SpawnPortals2Effect.gd")
	var t0 := Time.get_ticks_msec()

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world  # после add_child (грабля -s)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	world.add_child(sun)

	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.42, 0.46, 0.5)
	pm.material = fmat
	fmi.mesh = pm
	world.add_child(fmi)

	# маркер за B — должен быть ВИДЕН В ОКНЕ портала A (суть пробы)
	var mk := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.2, 1.2, 1.2)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.85, 0.1)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.75, 0.1)
	mm.emission_energy_multiplier = 2.0
	bmesh.material = mm
	mk.mesh = bmesh
	mk.position = Vector3(0, 1.2, -16)
	world.add_child(mk)
	var ml := Label3D.new()
	ml.text = "B-SIDE"
	ml.font_size = 150
	ml.position = Vector3(0, 2.5, -16)
	world.add_child(ml)

	# красный куб на камерной стороне (виден в окне B с задней пробы)
	var mk2 := MeshInstance3D.new()
	var bmesh2 := BoxMesh.new()
	bmesh2.size = Vector3(0.8, 0.8, 0.8)
	var mm2 := StandardMaterial3D.new()
	mm2.albedo_color = Color(0.9, 0.2, 0.15)
	mm2.emission_enabled = true
	mm2.emission = Color(0.9, 0.15, 0.1)
	mm2.emission_energy_multiplier = 1.5
	bmesh2.material = mm2
	mk2.mesh = bmesh2
	mk2.position = Vector3(-2.6, 0.9, 2.0)
	world.add_child(mk2)

	# пара: A(0,1.5,0) нормаль +Z (на камеру), B(0,1.5,-12) нормаль -Z
	var ps = load("res://Logic/PortalNode2.gd")
	var pair := Node3D.new()
	world.add_child(pair)
	var a = Area3D.new(); a.set_script(ps); pair.add_child(a)
	a.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 0))
	var b = Area3D.new(); b.set_script(ps); pair.add_child(b)
	var bba := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	b.global_transform = Transform3D(bba, Vector3(0, 1.5, -12))
	a.call("build", Color(0.25, 0.85, 0.8), 0.0)
	b.call("build", Color(0.85, 0.4, 1.0), 3.1)
	a.partner = b
	b.partner = a
	a.call("bind_ring")
	b.call("bind_ring")
	open_ms = Time.get_ticks_msec() - t0

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	await process_frame
	await process_frame
	print("[PORTAL2-VIEW] open_ms=%d" % open_ms)
	await _shot(cam, Vector3(0, 1.6, 3.5), Vector3(0, 1.5, 0),
		"res://_tmp_probe/portal2_view_front.png")
	await _shot(cam, Vector3(2.4, 1.1, 2.6), Vector3(0, 1.5, 0),
		"res://_tmp_probe/portal2_view_angle.png")
	await _shot(cam, Vector3(0, 1.7, -15.5), Vector3(0, 1.5, -12),
		"res://_tmp_probe/portal2_view_back.png")
	await _shot(cam, Vector3(0, 1.6, 1.2), Vector3(0, 1.5, 0),
		"res://_tmp_probe/portal2_view_close.png")
	await _shot(cam, Vector3(-2.0, 1.6, 2.0), Vector3(0, 1.5, 0),
		"res://_tmp_probe/portal2_view_parallaxL.png")
	await _shot(cam, Vector3(2.0, 1.6, 2.0), Vector3(0, 1.5, 0),
		"res://_tmp_probe/portal2_view_parallaxR.png")
	print("[PORTAL2-VIEW] done")
	quit(0)
