extends SceneTree

## Желе v5 рендер-проба (Q25-B риг «мувер + пин-кольцо», Тест №1 PASS):
## желе должно (1) держать купол с промином ~0.5 (посадка кольца) — не лужа
## и не «хотдог-гамак», (2) СДВИГАТЬСЯ от толчков (пинки по куполу + импульс
## муверу). Пин-кольцо низа — НОРМА v5 (проверяет 4-канальную механику
## probe_movepoint), «пинов 0» из v4 больше не гейт. PNG покой/после-толчков
## смотрю сам. БЕЗ --headless (run_godot_render.ps1).

const JellyScript = preload("res://Logic/JellyMonster.gd")

var fails := 0

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

## Живой AABB по точкам (как JellyMonster._physics_process).
func _aabb(jelly: Node) -> Dictionary:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for i in jelly.get_point_count():
		var p: Vector3 = jelly.get_point_transform(i)
		lo = lo.min(p)
		hi = hi.max(p)
	return {"lo": lo, "hi": hi}

func _init() -> void:
	await physics_frame
	# Конфиг из аргументов (после `--`): --jpressure=X --jprecision=Y
	var jpressure := 1.35
	var jprecision := 18
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--jpressure="):
			jpressure = float(a.get_slice("=", 1))
		elif a.begins_with("--jprecision="):
			jprecision = int(a.get_slice("=", 1))
	var ground := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(60, 4, 60) # толстый пол: тонкую статику софтбоди протыкает
	fcs.shape = fbox
	fcs.position = Vector3(0, -2.0, 0)
	ground.add_child(fcs)
	root.add_child(ground)
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

	var jelly = JellyScript.new()
	# Меш ДО add_child (грабля 4.8: назначение меша узлу уже в дереве
	# сбрасывает SoftBody3D — точки дают (0,0,0), проверено 19.11.26).
	jelly.mesh = JellyScript.build_blob_mesh(2.6)
	jelly.pressure_coefficient = jpressure
	jelly.simulation_precision = jprecision
	jelly.position = Vector3(0, 1.95, 0)
	root.add_child(jelly)
	await physics_frame
	print("[JELLY4] config: pressure=%.2f precision=%d" % [jpressure, jprecision])

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(5.5, 3.2, 7.5)
	cam.current = true

	# 1) оседание 2.5 с — форма покоя
	for i in 150:
		await physics_frame
	var bb0 := _aabb(jelly)
	var c0: Vector3 = (bb0.lo + bb0.hi) * 0.5
	_check("купол держится на кольце (высота ≥1.0 м)", bb0.hi.y - bb0.lo.y >= 1.0)
	_check("не расползается (ширина ≤ 8 м)",
			maxf(bb0.hi.x - bb0.lo.x, bb0.hi.z - bb0.lo.z) <= 8.0)
	print("[JELLY4] rest: lo=%s hi=%s" % [bb0.lo, bb0.hi])
	cam.look_at(c0)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_tmp_probe/jelly_v5_rest.png")

	# 1b) НИЗкий ракурс «глаза игрока» (~1.6 м, почти горизонт): артефакт
	# «полумесяца» (вердикт юзера 26.11.26: «ближняя сторона невидимая,
	# обрезается») проявлялся именно сбоку на высоте стоя. DEPTH_PRE_PASS
	# обязан держать купол цельным с любого угла — PNG смотрю сам.
	cam.position = Vector3(c0.x, 1.6, c0.z + 9.5)
	cam.look_at(Vector3(c0.x, 0.8, c0.z))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_tmp_probe/jelly_v5_lowangle.png")
	cam.position = Vector3(5.5, 3.2, 7.5)

	# 2) серия толчков с одного бока (как усиленный отжим игрока; кулдаун
	# jolt_from не мешает — каналы зовём напрямую). v5: удар = серия
	# apply_impulse по куполу (точка на поверхности!) + импульс муверу;
	# шары-пушеры не работают — контакт SoftBody-vs-RigidBody сломан
	# (изолят probe_softcontact).
	var body_h: float = bb0.hi.y - bb0.lo.y
	for hit in 4:
		var dir := Vector3(-1, 0, -0.25).normalized()
		jelly._poke_dome(
				c0 + dir * (jelly.radius * 0.8) + Vector3(0, body_h * 0.25, 0),
				-dir, 0.85)
		jelly._kick_mover(-dir, 120.0)
		for i in 30:
			await physics_frame
	var bb1 := _aabb(jelly)
	var c1: Vector3 = (bb1.lo + bb1.hi) * 0.5
	var shift := Vector2(c1.x - c0.x, c1.z - c0.z).length()
	print("[JELLY4] center0=%s center1=%s shift=%.2f м" % [c0, c1, shift])
	_check("желе СДВИНУЛОСЬ (>0.35 м)", shift > 0.35)
	_check("после толчков не лужа (высота ≥0.8 м)", bb1.hi.y - bb1.lo.y >= 0.8)
	_check("толчки не унесли за край пола (|центр|<25 м)", c1.length() < 25.0)
	cam.look_at(c1)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://_tmp_probe/jelly_v5_pushed.png")

	if fails == 0:
		print("JELLY4 GATE PASS")
	else:
		print("JELLY4 GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
