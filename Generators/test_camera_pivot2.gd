extends SceneTree
## Гейт регресса Q44-R «инверсия мыши при порталах» (вердикт юзера 26.11.26):
## pitch камеры теперь живёт скаляром _cam_pitch (SSOT), базис пивота
## пересобирается детерминированно каждый физ-тик, эйлер из маппнутого
## матрицей портала базиса больше не читается. Чеки:
##   1) Фаза 0: spring_arm.global == global * T(R_X(_cam_pitch), _shoulder);
##   2) Фаза 1 (перенос через пару; портал B НАКЛОНЁН — гимбал-зона старого
##      бага): ориентация пивота стабильна кадр-в-кадр (без дрейфа/флипа);
##   3) экран-pitch монотонен по _cam_pitch (мышь вверх = взгляд вверх);
##   4) после деспавна пары Фаза 0 восстанавливается ТОЧНО без переворота
##      (старый баг: испорченный rotation.x жил вечно). quit(0/1).

var _fails := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		print("[OK] " + label)
	else:
		_fails += 1
		printerr("[FAIL] " + label)

func _watchdog() -> void:
	await create_timer(30.0).timeout
	printerr("[WDT] TIMEOUT 30с — проба зависла")
	quit(1)

## Экран-pitch камеры: угол forward над горизонтом.
func _pitch_of(cam: Camera3D) -> float:
	return asin(clampf(-cam.global_basis.z.y, -1.0, 1.0))

func _init() -> void:
	_watchdog()
	await process_frame
	var ps = load("res://Logic/PortalNode2.gd")

	var player = (load("res://Scenes/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 3))
	var spring: Node3D = player.get("spring_arm")
	var cam: Camera3D = player.get("camera")
	_ck(spring != null and cam != null, "spring_arm/camera найдены")

	# Пара: A прямо, B НАКЛОНЁН (прицел в наклонную поверхность — гимбал-зона
	# старого бага: эйлер YXZ маппнутого базиса давал мусор).
	var pair := Node3D.new()
	root.add_child(pair)
	var a = Area3D.new(); a.set_script(ps); pair.add_child(a)
	a.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 0))
	var b = Area3D.new(); b.set_script(ps); pair.add_child(b)
	b.global_transform = Transform3D(
		Basis(Vector3(0, 1, 0), 1.1) * Basis(Vector3(1, 0, 0), -0.6),
		Vector3(10, 1.5, 0))
	a.call("build", Color.WHITE, 0.0, 30.0)
	b.call("build", Color.WHITE, 1.0, 30.0)
	a.partner = b
	b.partner = a
	a.call("bind_ring")
	b.call("bind_ring")

	await physics_frame
	await physics_frame

	# --- 1) Фаза 0: пивот = тело * R_X(pitch) ---
	player.set("_cam_pitch", 0.4)
	for i in 5:
		await physics_frame
	var want: Transform3D = player.global_transform \
		* Transform3D(Basis(Vector3(1, 0, 0), 0.4), player.get("_shoulder"))
	_ck(spring.global_transform.origin.distance_to(want.origin) < 0.01
		and spring.global_transform.basis.get_euler().x
			* want.basis.get_euler().x > 0.0,
		"Фаза 0: пивот = тело * R_X(pitch)")

	# --- 2) Фаза 1: перенос через A (как _transfer), наклонный B ---
	var m: Transform3D = a.portal_matrix()
	player.global_transform = m * Transform3D(Basis(Vector3(0, 1, 0), 2.0),
		Vector3(0, 1.5, 1.0))
	player.reset_physics_interpolation()
	player.set_meta("p2_entry", a)
	player.set_meta("p2_t0", Time.get_ticks_msec())
	var bases: Array = []
	for i in 8:
		await physics_frame
		bases.append(spring.global_basis)
	var stable := true
	for i in range(1, bases.size()):
		if not bases[i].is_equal_approx(bases[i - 1]):
			stable = false
	_ck(stable, "Фаза 1: ориентация пивота стабильна кадр-в-кадр")

	# --- 3) экран-pitch монотонен по _cam_pitch ---
	player.set("_cam_pitch", 0.2)
	for i in 4:
		await physics_frame
	var p1 := _pitch_of(cam)
	player.set("_cam_pitch", 0.6)
	for i in 4:
		await physics_frame
	var p2 := _pitch_of(cam)
	_ck(p2 > p1, "экран-pitch монотонен (%.3f < %.3f)" % [p1, p2])

	# --- 4) деспавн пары → Фаза 0 точно, без переворота ---
	pair.free()
	await process_frame
	player.set("_cam_pitch", 0.5)
	for i in 5:
		await physics_frame
	var want0: Transform3D = player.global_transform \
		* Transform3D(Basis(Vector3(1, 0, 0), 0.5), player.get("_shoulder"))
	_ck(spring.global_transform.origin.distance_to(want0.origin) < 0.01
		and spring.global_transform.basis.is_equal_approx(want0.basis),
		"деспавн: Фаза 0 восстановлена точно (переворота нет)")

	print("CAMPIVOT2 GATE: " + ("ALL PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)
