extends SceneTree

## Q31 рендер-проба: воронка промина шляпки (шейдер mushroom_cap.gdshader) —
## PNG смотрю сам. БЕЗ --headless (get_texture() null в headless); запуск
## через run_godot_render.ps1 (--quit-after 300: ловим промин ~100 кадров).
## Камера current=true ПОСЛЕДНЕЙ (грабля: камера игрока перехватывает current;
## look_at — только глобальные координаты).

const MUSH := "res://Graphics/Environment/Props/mushroom_bounce/mushroom_bounce.tscn"

func _init() -> void:
	await physics_frame
	# Пол-коллизия
	var ground := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 1, 40)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	ground.add_child(fcs)
	root.add_child(ground)
	# Свет + окружение (минимум, гриб в центре кадра)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	root.add_child(sun)
	var wenv := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.3, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.7
	wenv.environment = e
	root.add_child(wenv)
	# Гриб в (0,0,0) — шляпка top y≈2.32
	var mush: Node3D = (load(MUSH) as PackedScene).instantiate()
	root.add_child(mush)
	await physics_frame
	await physics_frame
	# Тело-тестер (падает, без ввода)
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	body.add_to_group("player")
	body.set_script(load("res://Generators/test_fall_body.gd"))
	root.add_child(body)
	await physics_frame
	# Камера ПОСЛЕДНЕЙ + current
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(4.8, 3.4, 5.2)
	cam.look_at(Vector3(0, 1.7, 0))
	cam.current = true
	# 1) PNG покоя (шляпка целая)
	for i in range(8):
		await process_frame
	_root_png("res://_tmp_probe/q31_mush_rest.png")
	print("[Q31R] rest PNG, dent=", mush.dent_current)
	# 2) дроп с 11 м → ловим пик промина (dent_current > 0.35)
	body.position = Vector3(0, 11.4, 0)
	body.velocity = Vector3.ZERO
	var waited := 0
	while mush.dent_current < 0.35 and waited < 300:
		await physics_frame
		waited += 1
	print("[Q31R] catch: dent=", mush.dent_current, " waited=", waited)
	# 3) PNG промина (2 кадров на дорисовку кадра)
	await process_frame
	await process_frame
	_root_png("res://_tmp_probe/q31_mush_dent.png")
	print("[Q31R] dent PNG, dent=", mush.dent_current)
	quit(0)

func _root_png(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
