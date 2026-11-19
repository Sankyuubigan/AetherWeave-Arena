extends SceneTree

## Гейт коллизии стола зачарований (Q37, репорт юзера «перс проходит сквозь
## стол»): CharacterBody3D пытается войти в стол test_move — ожидаем блок, и
## свободный ход в стороне — ожидаем проход. Запуск: godot -s (без --headless
## физика та же; можно headless).

func _init() -> void:
	await process_frame
	await process_frame
	var arena = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	for i in 5:
		await physics_frame

	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	cs.shape = cap
	body.add_child(cs)
	arena.add_child(body)
	# стол в (35.5, 0, 35.5) rot -45, масштаб 1.7 (полу-габарит ~0.87)
	body.global_position = Vector3(35.5, 1.0, 33.4)  # южнее стола на ~2 м
	for i in 3:
		await physics_frame

	var into := body.test_move(body.global_transform, Vector3(0, 0, 1.2))
	var away := body.test_move(body.global_transform, Vector3(0, 0, -1.2))
	print("GATE move_into_table=", into, " move_away=", away)
	var pass_ok := into and not away
	if pass_ok:
		print("COLLISION GATE ALL PASS")
	else:
		push_error("COLLISION GATE FAIL")
	quit(0 if pass_ok else 1)
