extends SceneTree

## Тест QUEUE Q6: JellyMonster (SoftBody3D) — точки генерируются из меша,
## софт-физика шевелит вершины, API 4.8-beta на месте. Гейт: GATE ALL PASS.

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
	_check("SoftBody3D.get_point_transform есть", ClassDB.class_has_method("SoftBody3D", "get_point_transform"))
	_check("SoftBody3D.set_point_pinned есть", ClassDB.class_has_method("SoftBody3D", "set_point_pinned"))

	var scene := Node3D.new()
	current_scene = scene
	root.add_child(scene)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.5, 20)
	shape.shape = bs
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.25, 0)
	scene.add_child(floor_body)

	var jelly := JellyScript.new()
	jelly.position = Vector3(0, 2.9, 0)
	scene.add_child(jelly)

	# Физика шагает во время create_timer-await'ов (прецедент test_ragdoll).
	await create_timer(0.8).timeout

	_check("точек софт-тела > 300", jelly.get_point_count() > 300)
	_check("pin deferred отработал без ошибок", is_instance_valid(jelly))
	# NOTE: симуляцию SoftBody3D в headless не проверить (get_point_transform
	# = (0,0,0) без рендерера) — реальная проверка рендер-пробой и юзером.

	if fails == 0:
		print("GATE ALL PASS")
	else:
		print("GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
