extends SceneTree
## ГДЕ У МОДЕЛИ ПЕРЕД (26.11.26). Три независимых источника:
##  A) носки (Toe − Foot) при wrapper.yaw = 0;
##  B) направление, в котором бежит персонаж при нажатии W (W = local −Z):
##     сравнить «куда едет» и «куда смотрят носки» — они ОБЯЗАНЫ совпадать;
##  C) смотрит ли камера в спину (базовое требование TPS).
## Запуск: --headless -s res://Generators/probe_model_forward.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 40:
		await physics_frame
	var skel := _find_skel(player)
	var wrapper = player.get_node_or_null("GraphicsWrapper")
	var cam: Camera3D = player.get_node_or_null("SpringArm3D/Camera3D")

	print("=== A) НОСКИ при wrapper.yaw = 0 ===")
	print("  ", _toe(skel), " => yaw %+.1f°" % rad_to_deg(atan2(_toe(skel).x, _toe(skel).z)))

	print("")
	print("=== B) БЕГ: W = local −Z. Куда едет тело и куда смотрят носки ===")
	# эмулируем ровно формулу PlayerController: global_dir = basis * (0,0,-1)
	player.rotation.y = 0.0
	wrapper.rotation.y = 0.0
	await physics_frame
	var local_dir := Vector3(0, 0, -1)
	var global_dir: Vector3 = player.global_transform.basis * local_dir
	print("  body.yaw=0: W → мировая скорость = ", global_dir.snapped(Vector3(0.01,0.01,0.01)))
	print("  target_angle (atan2(x,z)) = %+.1f°" % rad_to_deg(atan2(local_dir.x, local_dir.z)))
	wrapper.rotation.y = atan2(local_dir.x, local_dir.z)
	await physics_frame
	await physics_frame
	print("  носки после доворота = ", _toe(skel).snapped(Vector3(0.01,0.01,0.01)),
		" => yaw %+.1f°" % rad_to_deg(atan2(_toe(skel).x, _toe(skel).z)))
	print("  ВЕРДИКТ: носки ", "СОВПАДАЮТ с бегом (OK)" if _toe(skel).z < -0.7 else "НЕ совпадают с бегом (БАГ)")

	print("")
	print("=== C) камера и старт игры ===")
	print("  камера от тела: ", (cam.global_position - player.global_position).snapped(Vector3(0.01,0.01,0.01)))
	print("  камера смотрит: ", (-cam.global_transform.basis.z).snapped(Vector3(0.01,0.01,0.01)))
	wrapper.rotation.y = 0.0
	await physics_frame
	await physics_frame
	var t0 := _toe(skel)
	print("  СТАРТ (wrapper.yaw=0): носки ", t0.snapped(Vector3(0.01,0.01,0.01)),
		" => смотрит ", "В КАМЕРУ (БАГ стартовой позы)" if t0.z > 0.5 else "ОТ камеры (OK)")

	print("")
	print("=== D) а если развернуть обёртку на 180° на старте? ===")
	wrapper.rotation.y = PI
	await physics_frame
	await physics_frame
	var t1 := _toe(skel)
	print("  носки ", t1.snapped(Vector3(0.01,0.01,0.01)),
		" => смотрит ", "ОТ камеры (это и нужно)" if t1.z < -0.5 else "В камеру")
	quit(0)

func _toe(skel: Skeleton3D) -> Vector3:
	var v := Vector3.ZERO
	var n := 0
	for side in ["Left", "Right"]:
		var f := skel.find_bone("mixamorig_%sFoot" % side)
		var t := skel.find_bone("mixamorig_%sToeBase" % side)
		if f < 0 or t < 0:
			continue
		var fp: Vector3 = skel.global_transform * skel.get_bone_global_pose(f).origin
		var tp: Vector3 = skel.global_transform * skel.get_bone_global_pose(t).origin
		var d := tp - fp
		d.y = 0.0
		if d.length() > 0.01:
			v += d.normalized()
			n += 1
	if n == 0:
		return Vector3.ZERO
	return (v / float(n)).normalized()

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null
