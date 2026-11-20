extends SceneTree

## Q32 рендер-проба v2: следы на дюне — PNG смотрю сам. Уроки v1:
## фазы мерить create_timer (wall-time), НЕ process-кадрами (FPS 165 →
## 150 кадров = 0.9 с); свет скользящий (-38°) + ambient 0.45 — рельеф
## читается; камера ближе. БЕЗ --headless; run_godot_render.ps1 с Frames=900.

const SG := "res://Graphics/Environment/Props/soft_ground/soft_ground.tscn"

func _init() -> void:
	var wd := create_timer(30.0)
	wd.timeout.connect(func() -> void:
		print("[Q32R] WATCHDOG")
		quit(1))
	# Пол-коллизия большой (за краями патча)
	var ground := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(80, 1, 80)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	ground.add_child(fcs)
	root.add_child(ground)
	# Пол-визуал под патчем (чуть ниже против z-fight)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	floor_mi.position.y = -0.02
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.72, 0.66, 0.52)
	floor_mi.material_override = fmat
	root.add_child(floor_mi)
	# Свет: скользящий угол — рельеф следов в тенях
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
	# Дюна в origin
	var sg: Node3D = (load(SG) as PackedScene).instantiate()
	root.add_child(sg)
	await physics_frame
	await physics_frame
	# Болванка ходьбы: старт (-4,1.2,0), dir (1,0), 2 м/с
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	body.add_to_group("player")
	body.set_script(load("res://Generators/test_walk_body.gd"))
	body.position = Vector3(-4, 1.2, 0)
	body.move_dir = Vector2(1, 0)
	body.speed = 2.0
	root.add_child(body)
	await physics_frame
	# Камера ПОСЛЕДНЕЙ + current
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(3.4, 1.15, 2.9)
	cam.look_at(Vector3(-1.3, 0.15, 0))
	cam.current = true
	# 1) ходьба 3.2 с (wall-time!) → PNG следовой дорожки
	await create_timer(3.2).timeout
	_root_png("res://_tmp_probe/q32_soft_walk.png")
	print("[Q32R] walk PNG pos=", body.position, " floor=", body.is_on_floor())
	# 2) стояние 1.3 с → PNG промина стоя
	body.move_dir = Vector2(0, 0)
	await create_timer(1.3).timeout
	_root_png("res://_tmp_probe/q32_soft_stand.png")
	print("[Q32R] stand PNG pos=", body.position)
	quit(0)

func _root_png(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
