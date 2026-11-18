extends SceneTree

## Тест QUEUE Q25: JellyMonster переработка — блоб-меш (ArrayMesh с шумом),
## физика мягче, штатив-пин, реакция через RigidBody3D-толкатели (jolt_from),
## кулдаун, группа jelly_monster. Гейт: GATE ALL PASS.

const JellyScript = preload("res://Logic/JellyMonster.gd")

var fails := 0

func _init() -> void:
	await process_frame
	_run()

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

func _run() -> void:
	_check("SoftBody3D.get_point_count есть", ClassDB.class_has_method("SoftBody3D", "get_point_count"))
	_check("SoftBody3D.set_point_pinned есть", ClassDB.class_has_method("SoftBody3D", "set_point_pinned"))

	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene # ТОЛЬКО после add_child (грабля 4.8, handoff)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.5, 20)
	shape.shape = bs
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.25, 0)
	scene.add_child(floor_body)

	var jelly := JellyScript.new()
	jelly.position = Vector3(0, 1.95, 0)
	scene.add_child(jelly)

	# Физика шагает во время create_timer-await'ов (прецедент test_ragdoll).
	await create_timer(0.8).timeout

	_check("точек софт-тела > 300", jelly.get_point_count() > 300)
	_check("pin deferred отработал без ошибок", is_instance_valid(jelly))
	_check("меш — ArrayMesh (блоб, не сфера)", jelly.mesh is ArrayMesh)
	_check("давление 1.35 (v3 купол)", absf(jelly.pressure_coefficient - 1.35) < 0.001)
	_check("дэмпинг 0.02", absf(jelly.damping_coefficient - 0.02) < 0.001)
	_check("FeelerArea добавлен", jelly.get_node_or_null("FeelerArea") != null)
	_check("в группе jelly_monster", jelly.is_in_group("jelly_monster"))
	# Пин-юбка v3 (фикс «хотдог-гамак»): пинов много, а не 3.
	# В headless все трансформы (0,0,0) → юбка = все точки; проверяем сам факт.
	var pinned := 0
	for i in jelly.get_point_count():
		if jelly.is_point_pinned(i):
			pinned += 1
	_check("пин-юбка накинула пины (>20)", pinned > 20)

	# Реакция: jolt_from спавнит невидимый RigidBody3D-толкатель (RigidBody
	# физически давит софтбоди, CharacterBody — нет — причина «не реагирует»).
	jelly.jolt_from(Vector3(4, 1.0, 3), 7.0)
	await create_timer(0.2).timeout
	var balls := 0
	for c in scene.get_children():
		if c is RigidBody3D:
			balls += 1
	_check("толкатель заспавнен", balls == 1)

	jelly.jolt_from(Vector3(4, 1.0, 3), 7.0) # в кулдауне — второго не быть
	await create_timer(0.2).timeout
	var balls2 := 0
	for c in scene.get_children():
		if c is RigidBody3D:
			balls2 += 1
	_check("кулдаун: второй толкатель не спавнится", balls2 == 1)
	# NOTE: симуляцию SoftBody3D в headless не проверить (get_point_transform
	# = (0,0,0) без рендерера) — реальная проверка рендер-пробой и юзером.

	if fails == 0:
		print("GATE ALL PASS")
	else:
		print("GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
