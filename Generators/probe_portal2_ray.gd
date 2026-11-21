extends SceneTree
## Гейт Q44 шаг 4: хитскан-луч сквозь портал (PortalNode2.ray_through).
## 1) луч точно в диск мембраны A → {portal, t}; 2) продолжение из выхода B
## (portal_matrix: exit = M*hp, направление = M.basis*dir, остаток длины) бьёт цель ЗА выходом B;
## 3) луч мимо диска — не продолжается; 4) луч сзади мембраны — не входит;
## 5) повторный луч сразу же — работает (лучи без кулдауна).
## Точка интеграции: лучевых скиллов в проекте НЕТ (молния = homing-снаряд,
## враги тоже снарядами) — ray_through это SSOT-API для будущих лучевых
## оружий; интеграция = первый сегмент до ray_through, второй из exit = M*hp
## по направлению M.basis*dir на остаток длины (см. ниже в 2).

var _fails := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		print("[OK] " + label)
	else:
		_fails += 1
		printerr("[FAIL] " + label)

func _watchdog() -> void:
	await create_timer(30.0).timeout
	print("[WDT] TIMEOUT 30с — проба зависла")
	quit(1)

func _init() -> void:
	_watchdog()
	await process_frame
	await physics_frame
	var ps = load("res://Logic/PortalNode2.gd")
	var pair := Node3D.new()
	root.add_child(pair)
	var a = Area3D.new(); a.set_script(ps); pair.add_child(a)
	a.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 0))
	var b = Area3D.new(); b.set_script(ps); pair.add_child(b)
	b.global_transform = Transform3D(Basis(), Vector3(10, 1.5, 0))
	a.call("build", Color.WHITE, 0.0, 30.0)
	b.call("build", Color.WHITE, 1.0, 30.0)
	a.partner = b
	b.partner = a

	# Цель ЗА выходом B (выход смотрит +Z: тело/снаряд вылетает в +Z).
	var tb := StaticBody3D.new()
	var tbcs := CollisionShape3D.new()
	var tbsh := BoxShape3D.new()
	tbsh.size = Vector3(1, 1, 1)
	tbcs.shape = tbsh
	tb.add_child(tbcs)
	root.add_child(tb)
	tb.global_position = Vector3(10, 1.5, 3)

	# --- 1) луч точно в диск A ---
	var from := Vector3(0, 1.5, 6)
	var dir := Vector3(0, 0, -1)
	var r = ps.ray_through(from, dir, 20.0)
	_ck(not r.is_empty() and r["portal"] == a, "луч нашёл диск A")
	_ck(absf(float(r.get("t", 0)) - 6.0) < 0.1,
		"t на мембране A (t=%.2f)" % float(r.get("t", -1)))

	# --- 2) продолжение из выхода B: поворот + остаток длины ---
	# Рейкаст только из IDLE-контекста: после await physics_frame пространство
	# заблокировано → intersect_ray молча пуст (поймано 1-м прогоном).
	await process_frame
	# Q44-R: exit через единую матрицу M — точка В ПЛОСКОСТИ B (EXIT_EPS убран).
	var m: Transform3D = r["portal"].portal_matrix()
	var hp: Vector3 = from + dir * float(r["t"])
	var exit: Vector3 = m * hp
	var nd: Vector3 = (m.basis * dir).normalized()
	_ck(exit.distance_to(Vector3(10, 1.5, 0.0)) < 0.05,
		"выход РОВНО в плоскости B — EXIT_EPS убран")
	_ck(absf(nd.length() - 1.0) < 0.01, "модуль направления сохранён")
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		exit, exit + nd * (20.0 - float(r["t"])))
	var hit = space.intersect_ray(q)
	_ck(not hit.is_empty() and hit["position"].distance_to(
			Vector3(10, 1.5, 3)) < 0.6,
		"луч сквозь портал бьёт цель ЗА B (%s)" % [hit.get("position", Vector3.ZERO)])

	# --- 3) луч мимо диска ---
	var r2 = ps.ray_through(Vector3(2.5, 1.5, 6), Vector3(0, 0, -1), 20.0)
	_ck(r2.is_empty(), "луч мимо диска не продолжается")

	# --- 4) луч сзади мембраны (не входит спереди) ---
	var r3 = ps.ray_through(Vector3(0, 1.5, -6), Vector3(0, 0, 1), 20.0)
	_ck(r3.is_empty(), "луч сзади портала не проходит")

	# --- 5) повторный луч сразу же ---
	var r4 = ps.ray_through(from, dir, 20.0)
	_ck(not r4.is_empty(), "повторный луч сразу же — работает (лучи без кулдауна)")

	print("PORTAL2-RAY GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)
