extends SceneTree

## Q32-FIX рендер-проба «нет парения»: болванка с ВИДИМОЙ капсулой стоит
## в центре насыщенного промина — вид сбоку на уровне ботинок. PNG смотрю сам.
## БЕЗ --headless; запуск run_godot_render.ps1.

const SG := "res://Graphics/Environment/Props/soft_ground/soft_ground.tscn"

func _init() -> void:
	var wd := create_timer(30.0)
	wd.timeout.connect(func() -> void:
		printerr("[SGFR] WATCHDOG")
		quit(1))
	_run()

func _run() -> void:
	# пол-коллизия (за краями патча) + пол-визуал
	var ground := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(80, 1, 80)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	ground.add_child(fcs)
	root.add_child(ground)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	floor_mi.position.y = -0.02
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.72, 0.66, 0.52)
	floor_mi.material_override = fmat
	root.add_child(floor_mi)
	# свет скользящий + ambient (уроки probe_soft_ground_render v2)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -40, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var wenv := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.3, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.45
	wenv.environment = e
	root.add_child(wenv)

	var sg: Node3D = (load(SG) as PackedScene).instantiate()
	root.add_child(sg)
	await physics_frame
	await physics_frame
	# насыщенный промин в точке стояния (0,0)
	sg._stamp(Vector2(0, 0), 5.0, 1.0)
	sg._stamp(Vector2(0.15, 0.1), 5.0, 1.0)

	# болванка с капсулой-визуалом встаёт в центр промина
	var body := CharacterBody3D.new()
	var bcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	bcs.shape = cap
	body.add_child(bcs)
	var bmi := MeshInstance3D.new()
	var bmesh := CapsuleMesh.new()
	bmesh.radius = 0.35
	bmesh.height = 1.7
	bmi.mesh = bmesh
	body.add_child(bmi)
	body.add_to_group("player")
	body.set_script(load("res://Generators/test_walk_body.gd"))
	body.move_dir = Vector2(0, 0)
	body.position = Vector3(0, 2.5, 0)
	root.add_child(body)
	await create_timer(1.2).timeout

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(3.2, 0.5, 0.9)
	cam.look_at(Vector3(0, 0.25, 0))
	cam.current = true
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q32_float_side.png")
	print("[SGFR] side PNG pos=", body.position, " on_floor=", body.is_on_floor())

	cam.position = Vector3(2.2, 0.6, 2.6)
	cam.look_at(Vector3(-0.3, 0.2, -0.2))
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q32_float_side2.png")
	print("[SGFR] PNGs saved")
	quit(0)
