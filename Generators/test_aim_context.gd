extends SceneTree
## Тест _aim_context (SpellCasterComponent, 17.11.26, запрос юзера «метеор и
## гром юзаются по месту прицела КОНЦА каста, а не начала»): хелпер читает
## ТЕКУЩУЮ камеру на каждый вызов → два вызова с разными питчами камеры дают
## разные target_pos. Плюс базовые гарантии: пол под лучом, нормаль вверх,
## cast_origin у тела игрока.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	if ps == null:
		print("AIM-TEST FAIL: нет player.tscn")
		quit(1)
		return
	var player = ps.instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1, 0)
	await process_frame

	# Пол под луч: бокс 100x1x100, верх на y=0.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	await process_frame
	await process_frame

	var caster = load("res://Logic/SpellCasterComponent.gd").new()
	player.add_child(caster)
	await process_frame

	var skill = load("res://Logic/Skills/SkillDB.gd").get_skills()["meteor"]
	var cam = player.get_node("SpringArm3D/Camera3D")

	# Питч вниз ~34° — луч в пол в ~4 м, питч вниз ~11° — в ~10 м.
	cam.rotation = Vector3(-0.6, 0, 0)
	var c1: Dictionary = caster._aim_context(player, "meteor", skill, "Right")
	cam.rotation = Vector3(-0.2, 0, 0)
	var c2: Dictionary = caster._aim_context(player, "meteor", skill, "Right")

	var ok := true
	if c1.is_empty() or c2.is_empty():
		print("AIM-TEST FAIL: контекст пуст c1=", c1.size(), " c2=", c2.size())
		ok = false
	else:
		print("AIM-TEST: c1.target_pos=", c1["target_pos"])
		print("AIM-TEST: c2.target_pos=", c2["target_pos"])
		if absf(c1["target_pos"].y) > 0.01 or absf(c2["target_pos"].y) > 0.01:
			print("AIM-TEST FAIL: прицел не на полу (y c1=%.2f c2=%.2f)" % [c1["target_pos"].y, c2["target_pos"].y])
			ok = false
		if not (c2["target_pos"].length() > c1["target_pos"].length() + 2.0):
			print("AIM-TEST FAIL: смена питча камеры не сместила прицел")
			ok = false
		if c1["hit_normal"].y < 0.9:
			print("AIM-TEST FAIL: нормаль не пола: ", c1["hit_normal"])
			ok = false
		if c1["target_node"] != floor_body:
			print("AIM-TEST FAIL: target_node не пол")
			ok = false
		var co: Vector3 = c1["cast_origin"]
		if co.distance_to(player.global_position) > 2.5:
			print("AIM-TEST FAIL: cast_origin далеко от тела: ", co)
			ok = false

	if not ok:
		quit(1)
		return
	print("AIM-TEST: ALL PASS")
	quit(0)
