extends SceneTree
## ДИАГНОЗ (26.11.26): рука сердечка уходит ВБОК — это клип или поворот тела?
## Юзер: «руки то влево то вправо вытягивает а не вперед, я же прицел держу
## прямо вперёд» + подозрение «тот же баг с 90 градусами».
##
## Меряем в МИРОВЫХ осях на ЖИВОМ игроке: камера смотрит в −Z (body yaw 0),
## wrapper = π (как в игре, спиной к камере). Играем клип через реальный
## PlayerAnimationComponent. Для каждой кисти считаем:
##   fwd  = проекция (кисть − центр) на направление прицела (мировой −Z)
##   side = боковая составляющая (|x|)
## Если поворот тела правильный, но fwd мал, а side велик → это КЛИП (жест
## широкий), а не баг осей. Если side≈0 и fwd велик, а юзер видит вбок →
## баг поворота тела.
## Запуск: --headless -s res://Generators/probe_heart_world.gd -- <клип>...

const PLAYER_SCENE := "res://Scenes/player.tscn"
const FPS := 30.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var names: Array = OS.get_cmdline_user_args()
	if names.is_empty():
		names = ["Spell_Cast"]
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await physics_frame
	# Как в игре после фикса: тело yaw 0, обёртка π (спиной к камере).
	player.rotation.y = 0.0
	var wrapper: Node3D = player.get_node_or_null("GraphicsWrapper")
	wrapper.rotation.y = PI
	var skel := _skel(player)
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if skel == null or comp == null:
		print("HEART FAIL: нет скелета/компонента")
		quit(1)
		return
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")
	# Направление прицела в мире: камера смотрит в −Z при body yaw 0.
	var aim_dir := Vector3(0, 0, -1)
	print("aim_dir(мир) = %s ; body.yaw=0 wrapper.yaw=π" % aim_dir)

	for n in names:
		var name := String(n)
		if not comp.has_cast_anim(name):
			print("HEART: нет клипа ", name)
			continue
		comp.play_cast_anim(name)
		var len: float = comp.cast_last_len()
		print("=== %s (%.2fс, реальный клип) ===" % [name, len])
		var best_f := -1e9
		var best_f_t := 0.0
		var best_s := 0.0
		## Максимальный боковой вынос ЛЮБОЙ кисти за клип — «насколько жест
		## широкий». Юзер видит «руки в стороны», когда эта величина велика.
		var max_side := 0.0
		var max_side_t := 0.0
		var t := 0.0
		var rows: Array[String] = []
		while t <= len + 0.0001:
			await process_frame
			var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
			var pr: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri).origin
			var pl: Vector3 = skel.global_transform * skel.get_bone_global_pose(li).origin
			var dr := pr - c
			var dl := pl - c
			dr.y = 0.0
			dl.y = 0.0
			var use := dr if dr.dot(aim_dir) > dl.dot(aim_dir) else dl
			var fwd := use.dot(aim_dir)
			var side := absf(use.x)
			# Боковой вынос считаем для ОБЕИХ кистей относительно центра.
			var s_any := maxf(absf(dr.x), absf(dl.x))
			if s_any > max_side:
				max_side = s_any
				max_side_t = t
			if fwd > best_f:
				best_f = fwd
				best_f_t = t
				best_s = side
			if fmod(t, 0.2) < 1.0 / FPS:
				rows.append("  t=%.2f  рабочая: fwd=%+.2f side=%.2f  (R fwd=%+.2f L fwd=%+.2f)  |x|обеих=%.2f" % [
					t, fwd, side, dr.dot(aim_dir), dl.dot(aim_dir), s_any])
			t += 1.0 / FPS
		for r in rows:
			print(r)
		print("  ПИК fwd=%+.2f м (side=%.2f) на t=%.2f | макс |x| любой кисти=%.2f на t=%.2f" % [
			best_f, best_s, best_f_t, max_side, max_side_t])
		print("  ВЕРДИКТ: %s" % ("ШИРОКИЙ ЖЕСТ (рука уходит в сторону)" \
			if max_side > best_f else "чистый вынос вперёд"))
	quit(0)

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skel(c)
		if r != null:
			return r
	return null
