extends SceneTree
## Верификация HeightMapShape3D для коллизии дюны (кандидат на «коллизия
## следует за проминами»): (1) размер ячейки (фикс. 1 м?), (2) оси/порядок
## map_data, (3) работает ли uniform scale на CollisionShape3D, (4) перф
## move_and_slide vs convex-хулл.
## Запуск: timeout 90 godot --headless -s res://Generators/probe_hm_shape.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ── Тест 1+2: гребни по X и по Z в одной карте 13×13 ──
	var hm := HeightMapShape3D.new()
	hm.map_width = 13
	hm.map_depth = 13
	var data := PackedFloat32Array()
	data.resize(13 * 13)
	# гребень A: i=9 (кандидат на ось X), высота 1.0; гребень B: j=9 (ось Z), 0.5
	for j in range(13):
		for i in range(13):
			data[j * 13 + i] = 1.0 if i == 9 else (0.5 if j == 9 else 0.0)
	hm.map_data = data

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = hm
	body.add_child(cs)
	root.add_child(body)
	for i in range(3):
		await physics_frame

	var space := root.get_world_3d().direct_space_state
	# скан вдоль X при z=0: где гребень 1.0?
	var ridge_x := -99.0
	for xi in range(-70, 71):
		var x := xi * 0.1
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 3, 0), Vector3(x, -1, 0))
		var hit := space.intersect_ray(q)
		if hit and hit.position.y > 0.6:
			ridge_x = x
			break
	# скан вдоль Z при x=0: где гребень 0.5?
	var ridge_z := -99.0
	for zi in range(-70, 71):
		var z := zi * 0.1
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(0, 3, z), Vector3(0, -1, z))
		var hit2 := space.intersect_ray(q2)
		if hit2 and hit2.position.y > 0.25 and hit2.position.y < 0.75:
			ridge_z = z
			break
	print("[HM] гребень 1.0 найден на x=%.1f (i=9); гребень 0.5 на z=%.1f (j=9)" % [ridge_x, ridge_z])
	print("[HM] вывод: x = i - %.1f; z = j - %.1f (ячейка %s)" % [9.0 - ridge_x, 9.0 - ridge_z,
			"1 м" if absf(9.0 - ridge_x - 3.0) < 0.15 else "НЕ 1 м"])

	# ── Тест 3: uniform scale 0.5 на CollisionShape3D ──
	var hm2 := HeightMapShape3D.new()
	hm2.map_width = 25
	hm2.map_depth = 25
	var d2 := PackedFloat32Array()
	d2.resize(25 * 25)
	for j in range(25):
		for i in range(25):
			d2[j * 25 + i] = 1.0 if i == 12 else 0.0
	hm2.map_data = d2
	var body2 := StaticBody3D.new()
	body2.position = Vector3(30, 0, 0)  # в стороне
	var cs2 := CollisionShape3D.new()
	cs2.shape = hm2
	cs2.scale = Vector3(0.5, 0.5, 0.5)  # uniform
	body2.add_child(cs2)
	root.add_child(body2)
	for i in range(3):
		await physics_frame
	var ridge_x2 := -99.0
	var ridge_h2 := -1.0
	for xi in range(200, 400):
		var x := xi * 0.1  # 20..40 вокруг body2.x=30
		var q3 := PhysicsRayQueryParameters3D.create(Vector3(x, 3, 0), Vector3(x, -1, 0))
		var hit3 := space.intersect_ray(q3)
		if hit3 and hit3.position.y > 0.3:
			ridge_x2 = x - 30.0
			ridge_h2 = hit3.position.y
			break
	print("[HM] scale 0.5: гребень на x=%.1f от центра, высота %.2f (ожидание: x=0, h=0.5)" % [ridge_x2, ridge_h2])

	# ── Тест 4: перф move_and_slide на heightmap vs convex ──
	# Чистый мир: болванка-капсула на дюне (heightmap 25×25 scale 0.5, база
	# 0.32 в центре), 300 тиков стоя + 300 тиков бега; метрика = длительность
	# самого вызова move_and_slide (коллизия-разрешение синхронно в вызове).
	var hm3 := HeightMapShape3D.new()
	hm3.map_width = 25
	hm3.map_depth = 25
	var d3 := PackedFloat32Array()
	d3.resize(25 * 25)
	for j in range(25):
		for i in range(25):
			var lx := (i - 12) * 0.5
			var lz := (j - 12) * 0.5
			var r := maxf(absf(lx), absf(lz)) / 6.0
			d3[j * 25 + i] = 0.32 * smoothstep(1.0, 0.75, r)
	hm3.map_data = d3
	var sg := StaticBody3D.new()
	var cs3 := CollisionShape3D.new()
	cs3.shape = hm3
	cs3.scale = Vector3(0.5, 0.5, 0.5)
	sg.add_child(cs3)
	root.add_child(sg)
	var cap := CharacterBody3D.new()
	var cshape := CapsuleShape3D.new()
	cshape.radius = 0.35
	cshape.height = 1.7
	var ccs := CollisionShape3D.new()
	ccs.shape = cshape
	cap.add_child(ccs)
	cap.position = Vector3(0, 1.0, 0)
	root.add_child(cap)
	for i in range(5):
		await physics_frame
	cap.velocity = Vector3.ZERO
	var worst := 0.0
	var total := 0.0
	var n := 0
	for i in range(300):
		cap.velocity = Vector3.ZERO
		var t0 := Time.get_ticks_usec()
		cap.move_and_slide()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, dt)
		total += dt
		n += 1
		await physics_frame
	print("[HM] стоя на дюне: средн %.3f мс, worst %.3f мс (%d тиков)" % [total / n, worst, n])
	worst = 0.0
	total = 0.0
	n = 0
	for i in range(300):
		cap.velocity = Vector3(0, -0.5, -4.0)
		var t0 := Time.get_ticks_usec()
		cap.move_and_slide()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, dt)
		total += dt
		n += 1
		await physics_frame
	print("[HM] бег по дюне: средн %.3f мс, worst %.3f мс" % [total / n, worst])
	print("[HM] PROBE DONE")
	quit(0)
