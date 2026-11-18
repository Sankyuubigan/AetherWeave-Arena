extends SceneTree
## Зонд фриза v5 (19.11.26): ВОСПРОИЗВЕДЕНИЕ упора в валун. Улика ловца:
## все стылы на (5.82,1.0,-3.02) = вплотную к валуну, микро-дрожь Y =
## депенетрация; build_env_prop.gd:233 даёт КАЖДОМУ пропу trimesh-коллизию
## (ConcavePolygonShape3D от 13.5K меша) — класс Godot issue #70453.
## Чистый эксперимент БЕЗ скрипта игрока: своё CharacterBody3D-капсула
## толкается в валун. Бисекция в одном прогоне: P2 = тримеш, P3 = convex hull
## (create_convex_shape(clean,simplify)). Если P2 стылы и P3 чисто —
## вина trimesh-контакта доказана, фикс = convex-коллизия пропов.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var arena: Node = (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	for i in 30:
		await process_frame

	# Валун: StaticBody3D около (5,0,-3)
	var boulder_body: StaticBody3D = null
	for n in arena.find_children("", "StaticBody3D", true, false):
		if (n as Node3D).global_position.distance_to(Vector3(5, 0, -3)) < 1.5:
			boulder_body = n
			break
	if boulder_body == null:
		print("BF5 ВАЛУН НЕ НАЙДЕН")
		quit(1)
		return
	var col: CollisionShape3D = boulder_body.find_children("", "CollisionShape3D", true, false)[0]
	var mi: MeshInstance3D = boulder_body.find_children("", "MeshInstance3D", true, false)[0]
	print("BF5 валун=%s trimesh_faces=%d" % [boulder_body.name, (col.shape as ConcavePolygonShape3D).get_faces().size() / 3])

	# Тестовое тело: капсула без скрипта
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	arena.add_child(body)
	body.global_position = Vector3(6.5, 0.9, -3.0)

	# P1: базлайн — просто стоит рядом (без контакта)
	var p1: Vector3 = await _push(body, 120, false)
	print("BF5 P1-идл-рядом: worst_tick=%.2fms worst_frame=%.1fms %s" % [p1.x, p1.y, p1.z])

	# P2: толкучка в тримеш валуна
	var p2: Vector3 = await _push(body, 300, true)
	print("BF5 P2-упор-ТРИМЕШ: worst_tick=%.2fms worst_frame=%.1fms %s" % [p2.x, p2.y, p2.z])

	# P3: свап коллизии на convex hull — та же толкучка
	var conv: ConvexPolygonShape3D = mi.mesh.create_convex_shape(true, true)
	print("BF5 convex_points=%d" % conv.points.size())
	col.shape = conv
	var p3: Vector3 = await _push(body, 300, true)
	print("BF5 P3-упор-CONVEX: worst_tick=%.2fms worst_frame=%.1fms %s" % [p3.x, p3.y, p3.z])

	quit(0)

## Толкучка/идл: per-tick время move_and_slide + per-frame дельта.
func _push(body: CharacterBody3D, n: int, push: bool) -> Vector3:
	var worst_tick := 0.0
	var worst_frame := 0.0
	var slow_ticks := 0
	var slow_frames := 0
	var max_contacts := 0
	for i in n:
		if push:
			await physics_frame
			var t1 := Time.get_ticks_usec()
			body.velocity = Vector3(-2, 0, 0)
			body.move_and_slide()
			var ms := (Time.get_ticks_usec() - t1) / 1000.0
			if ms > 5.0:
				slow_ticks += 1
				print("BF5   медленный тик %d: move_and_slide=%.1fms контактов=%d" % [
					i, ms, body.get_slide_collision_count()])
			max_contacts = maxi(max_contacts, body.get_slide_collision_count())
			worst_tick = maxf(worst_tick, ms)
		var f0 := Time.get_ticks_usec()
		await process_frame
		var fms := (Time.get_ticks_usec() - f0) / 1000.0
		if fms > 50.0:
			slow_frames += 1
			print("BF5   медленный кадр %d: %.0fms" % [i, fms])
		worst_frame = maxf(worst_frame, fms)
	return Vector3(worst_tick, worst_frame, float(slow_ticks * 1000 + slow_frames))

## Расшифровка z: slow_ticks*1000 + slow_frames.
