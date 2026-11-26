extends SceneTree
## Проверка ГЛАВНОГО сценария бага: перс БЕЖИТ (wrapper.yaw = π, спиной к камере),
## останавливается и кастует. Смотрим, поворачивается ли он при этом.
## И заодно: куда он смотрит при СТАРТЕ игры (wrapper.yaw = 0).
## Запуск: --headless -s res://Generators/probe_cast_after_run.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await physics_frame
	var wrapper = player.get_node_or_null("GraphicsWrapper")
	var skel := _find_skel(player)
	var sc = player.get_node_or_null("SpellCasterComponent")
	var comp = player.get_node_or_null("PlayerAnimationComponent")

	print("=== СТАРТ ИГРЫ (wrapper.yaw = %.0f°) ===" % rad_to_deg(wrapper.rotation.y))
	print("  носки = ", _toe(skel, wrapper), " => смотрит ", _dir(_toe(skel, wrapper)))
	print("  камера стоит сзади (+Z) и смотрит в −Z")
	print("  => при старте перс смотрит ", "В КАМЕРУ" if _toe(skel, wrapper).z > 0.0 else "ОТ камеры")

	print("")
	print("=== ПОСЛЕ БЕГА «ВПЕРЁД» (wrapper.yaw = 180°) ===")
	wrapper.rotation.y = PI
	await physics_frame
	await physics_frame
	print("  носки = ", _toe(skel, wrapper), " => смотрит ", _dir(_toe(skel, wrapper)))
	print("  => спиной к камере (как в видео юзера) — ОЖИДАЕМО")

	print("")
	print("=== КАСТ: перс бежит, останавливается, кастует вперёд ===")
	print("  (камера смотрит в −Z, цель — перед камерой)")
	for pitch_deg in [-10.0, -30.0, -45.0, -60.0, -75.0]:
		wrapper.rotation.y = PI
		player.rotation.y = 0.0
		await physics_frame
		var before := _toe(skel, wrapper)
		player._cam_pitch = deg_to_rad(pitch_deg)
		for i in 3:
			await physics_frame
		# ровно то, что делает _ik_begin
		var aim: Vector3 = sc._aim_dir_point(player, 30.0)
		player.face_aim_target(aim, 1.0)
		for i in 40:
			await physics_frame
		var after := _toe(skel, wrapper)
		var turned := absf(rad_to_deg(wrapf(atan2(after.x, after.z) - atan2(before.x, before.z), -PI, PI)))
		print("  pitch %+4.0f°: было %-14s стало %-14s поворот %5.1f° %s" % [
			pitch_deg, _dir(before), _dir(after), turned,
			"OK (не крутится)" if turned < 15.0 else "БАГ: развернуло"])

	print("")
	print("=== СТАРЫЙ КОД (точка рейкаста) — для сравнения ===")
	for pitch_deg in [-10.0, -45.0, -60.0, -75.0]:
		wrapper.rotation.y = PI
		player.rotation.y = 0.0
		await physics_frame
		var before := _toe(skel, wrapper)
		player._cam_pitch = deg_to_rad(pitch_deg)
		for i in 3:
			await physics_frame
		var aim: Vector3 = sc._aim_point(player, 30.0)
		var d: Vector3 = aim - player.global_position
		d.y = 0.0
		player.face_aim_target(aim, 1.0)
		for i in 40:
			await physics_frame
		var after := _toe(skel, wrapper)
		var turned := absf(rad_to_deg(wrapf(atan2(after.x, after.z) - atan2(before.x, before.z), -PI, PI)))
		print("  pitch %+4.0f°: точка (%.1f,%.1f) yaw=%+.0f° → поворот %5.1f° %s" % [
			pitch_deg, d.x, d.z, rad_to_deg(atan2(d.x, d.z)), turned,
			"БАГ" if turned > 20.0 else "ok"])
	quit(0)

func _toe(skel: Skeleton3D, _w) -> Vector3:
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

func _dir(d: Vector3) -> String:
	if d.length() < 0.01:
		return "?"
	return "%s(%+.0f°)" % [
		"−Z" if absf(d.z + 1.0) < 0.3 else ("+Z" if absf(d.z - 1.0) < 0.3 else "бок"),
		rad_to_deg(atan2(d.x, d.z))]

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
