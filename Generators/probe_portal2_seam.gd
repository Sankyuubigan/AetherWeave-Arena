extends SceneTree
## Рендер-гейт приёмки Q44-R «шов невидим» (ДОПИСЬ 15 п.3; чек-лист спеца
## §2 п.5, 05-ответ.md = ССОТ). Кадры: подход 1.0 м → 0.15 м → +0.02 м
## (до свопа) → СВОП-кадр: главная камера = portal_matrix()*поза(+0.02)
## (= (10,1.5,−0.02), взгляд +Z наружу от B — та же поза, из которой окно
## рендерило картинку). Гейт: +0.02 vs −0.02 ПОПИКСЕЛЬНО (mean<3, 95%<16;
## res_override=1.0 у обоих окон — без апскейла). Плюс аватар-кадр: капсула
## на (10,1.5,2.5) видна СКВОЗЬ ОКНО с камеры на стороне A (камера z=+1.2:
## окно-камера (10,1.5,1.2) смотрит +Z и видит z>1.2 — аватар в кадре;
## плановая «камера z=+3» несовместима с аватаром на z=2 — mapped-камера
## была бы позади аватара, поза скорректирована на 1.2 м = геометрия Фазы 1).
## Маркеры: зелёный AVATAR за B, циан FRONT-B, магента BEHIND-B (в окно НЕ
## имеет права попасть). Зеркальный текст лейблов в окне — НЕ дефект:
## mapped-камера смотрит на мир с другой стороны, лейблы честно видны со
## спины (проверено 26.11: кадры 2-5 = живое окно, аватар растёт при
## подходе, своп-кадр ≈ окно 0.44/2.0). PNG лично смотрит агент. quit(0/1).

var _fails := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		print("[OK] " + label)
	else:
		_fails += 1
		printerr("[FAIL] " + label)

func _watchdog() -> void:
	await create_timer(60.0).timeout
	printerr("[WDT] TIMEOUT 60с — seam-проба зависла")
	quit(1)

func _shot_pose(cam: Camera3D, pose: Transform3D, path: String) -> void:
	cam.global_transform = pose
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

## mean/p95 по максимальному канальному |Δ| (0..255) двух PNG.
func _diff(pa: String, pb: String) -> Dictionary:
	var ia := Image.load_from_file(ProjectSettings.globalize_path(pa))
	var ib := Image.load_from_file(ProjectSettings.globalize_path(pb))
	if ia == null or ib == null or ia.get_size() != ib.get_size():
		return {"mean": 999.0, "p95": 999.0}
	var w := ia.get_width()
	var h := ia.get_height()
	var total := 0.0
	var all := PackedFloat32Array()
	all.resize(w * h)
	var i := 0
	for y in h:
		for x in w:
			var ca := ia.get_pixel(x, y)
			var cb := ib.get_pixel(x, y)
			var d := maxf(absf(ca.r - cb.r),
				maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) * 255.0
			total += d
			all[i] = d
			i += 1
	all.sort()
	var p95: float = all[int(all.size() * 0.95)]
	return {"mean": total / float(w * h), "p95": p95}

func _set_res(n: Node, v: float) -> void:
	if "res_override" in n:
		n.set("res_override", v)
	for c in n.get_children():
		_set_res(c, v)

func _init() -> void:
	_watchdog()
	await process_frame
	var _pre1 = load("res://Logic/PortalNode2.gd")
	var _pre2 = load("res://Graphics/PortalRing2.gd")

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world  # после add_child (грабля -s)

	# Анти-алиасинг главного вьюпорта выкл: сравнение шва должно быть про
	# математику, а не про разницу AA у main/SubViewport.
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa = false

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	world.add_child(sun)

	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.42, 0.46, 0.5)
	pm.material = fmat
	fmi.mesh = pm
	world.add_child(fmi)

	# Красный куб на камерной стороне A (контекст кадра).
	_box(world, Vector3(-2.6, 0.9, 2.0), Vector3(0.8, 0.8, 0.8),
		Color(0.9, 0.2, 0.15), "A-SIDE")
	# Зелёный аватар ЗА B (виден сквозь окно — суть приёмки спеца).
	_box(world, Vector3(10, 0.75, 2.5), Vector3(0.7, 1.5, 0.7),
		Color(0.2, 0.95, 0.3), "AVATAR")
	# Циан ПЕРЕД B (содержимое окна).
	_box(world, Vector3(11.5, 1.0, 5.0), Vector3(1.0, 1.0, 1.0),
		Color(0.1, 0.8, 0.95), "FRONT-B")
	# Магента ЗА плоскостью B (в окно попасть НЕ имеет права).
	_box(world, Vector3(8.5, 1.0, -3.0), Vector3(1.0, 1.0, 1.0),
		Color(0.95, 0.15, 0.95), "BEHIND-B")

	# Симметричная пара A(0,1.5,0)/B(10,1.5,0), обе нормалью +Z (как в
	# test_portals2 и арифметике ДОПИСИ 14).
	var ps = load("res://Logic/PortalNode2.gd")
	var pair := Node3D.new()
	world.add_child(pair)
	var a = Area3D.new(); a.set_script(ps); pair.add_child(a)
	a.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 0))
	var b = Area3D.new(); b.set_script(ps); pair.add_child(b)
	b.global_transform = Transform3D(Basis(), Vector3(10, 1.5, 0))
	a.call("build", Color(0.25, 0.85, 0.8), 0.0)
	b.call("build", Color(0.85, 0.4, 1.0), 3.1)
	a.partner = b
	b.partner = a
	a.call("bind_ring")
	b.call("bind_ring")
	# Пиксель-в-пиксель гейт: окно в полном разрешении главного вьюпорта.
	_set_res(a, 1.0)
	_set_res(b, 1.0)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	await process_frame
	await process_frame

	# --- 1) подход 1.0 м ---
	await _shot_pose(cam, Transform3D(Basis(), Vector3(0, 1.5, 1.0)),
		"res://_tmp_probe/portal2_seam_1m.png")
	# --- 2) подход 0.15 м ---
	await _shot_pose(cam, Transform3D(Basis(), Vector3(0, 1.5, 0.15)),
		"res://_tmp_probe/portal2_seam_15cm.png")
	# --- 3) +0.02 м (последний кадр ДО свопа) ---
	await _shot_pose(cam, Transform3D(Basis(), Vector3(0, 1.5, 0.02)),
		"res://_tmp_probe/portal2_seam_2cm.png")
	# --- 4) СВОП-кадр: главная камера = M * поза(+0.02) ---
	var swap_pose: Transform3D = a.portal_matrix() \
		* Transform3D(Basis(), Vector3(0, 1.5, 0.02))
	print("[SEAM] swap pose: origin=%s fwd=%s" % [
		swap_pose.origin, (swap_pose.basis * Vector3(0, 0, -1))])
	await _shot_pose(cam, swap_pose,
		"res://_tmp_probe/portal2_seam_swap.png")
	# --- 5) аватар сквозь окно (камера на A, z=+1.2) ---
	await _shot_pose(cam, Transform3D(Basis(), Vector3(0, 1.5, 1.2)),
		"res://_tmp_probe/portal2_seam_avatar.png")

	# --- гейт: +0.02 vs своп(−0.02) попиксельно ---
	var d := _diff("res://_tmp_probe/portal2_seam_2cm.png",
		"res://_tmp_probe/portal2_seam_swap.png")
	print("[SEAM] diff mean=%.2f p95=%.1f (гейт: mean<3, p95<16)" %
		[d["mean"], d["p95"]])
	_ck(d["mean"] < 3.0, "шов mean=%.2f < 3" % d["mean"])
	_ck(d["p95"] < 16.0, "шов p95=%.1f < 16" % d["p95"])

	print("[SEAM] " + ("GATE PASS — PNG в _tmp_probe/, смотреть лично"
		if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)

func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color,
		label: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.2
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	var lb := Label3D.new()
	lb.text = label
	lb.font_size = 96
	lb.position = pos + Vector3(0, size.y * 0.5 + 0.45, 0)
	parent.add_child(lb)
