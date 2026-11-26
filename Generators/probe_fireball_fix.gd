extends SceneTree
## ПРИЁМКА (26.11.26): фаербол после фикса — правая рука + ускорение вдвое.
## Проверяем ФАКТЫ, а не настройки:
##  1) cast_hand == "Right" и это ТА рука, что реально выбрасывается вперёд
##     (замер кисти в момент spawn_delay: правая должна быть впереди левой);
##  2) cast_speed 2.0 реально сокращает окно клипа (cast_last_len ≈ 1.15 с);
##  3) spawn_delay попадает в пик выноса ПРАВОЙ кисти (не после возврата).
## Запуск: --headless -s res://Generators/probe_fireball_fix.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await physics_frame
	player.rotation.y = 0.0
	var wrapper: Node3D = player.get_node_or_null("GraphicsWrapper")
	wrapper.rotation.y = PI
	var skel := _skel(player)
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	var skills = load("res://Logic/Skills/SkillDB.gd").get_skills()
	if not skills.has("fireball"):
		print("FIREBALL FAIL: нет скилла fireball")
		quit(1)
		return
	var fb = skills["fireball"]
	var fails: Array[String] = []

	print("=== настройки скилла ===")
	print("  cast_anim   = %s" % fb.cast_anim)
	print("  cast_hand   = %s (ожидалось Right)" % fb.cast_hand)
	print("  cast_speed  = %.2f (ожидалось 2.0)" % fb.cast_speed)
	print("  spawn_delay = %.2f с" % _spawn_delay_of(fb))
	if fb.cast_hand != "Right":
		fails.append("cast_hand = %s, ожидалось Right" % fb.cast_hand)
	if absf(fb.cast_speed - 2.0) > 0.01:
		fails.append("cast_speed = %.2f, ожидалось 2.0" % fb.cast_speed)

	# Реальное окно клипа с учётом темпа.
	comp.play_cast_anim(fb.cast_anim, fb.cast_speed)
	var real_len: float = comp.cast_last_len()
	print("  реальная длина клипа при cast_speed=2: %.3f с (без ускорения 2.300)" % real_len)
	if real_len > 1.40:
		fails.append("клип не ускорился: %.2f с" % real_len)

	# Кисть в момент спавна: правая должна быть ВПЕРЕДИ левой.
	var delay: float = _spawn_delay_of(fb)
	comp.play_cast_anim(fb.cast_anim, fb.cast_speed)
	var elapsed := 0.0
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")
	while elapsed < delay:
		await process_frame
		elapsed += get_root().get_process_delta_time()
	var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
	var pr: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri).origin
	var pl: Vector3 = skel.global_transform * skel.get_bone_global_pose(li).origin
	var aim := Vector3(0, 0, -1)   # камера смотрит в −Z
	var fr := (pr - c).dot(aim)
	var fl := (pl - c).dot(aim)
	print("=== кисти в момент спавна (t=%.2f с реального) ===" % elapsed)
	print("  правая fwd=%+.2f м | левая fwd=%+.2f м" % [fr, fl])
	if fr <= fl:
		fails.append("в момент спавна правая (%.2f) НЕ впереди левой (%.2f)" % [fr, fl])
	elif fr < 0.25:
		fails.append("правая рука в момент спавна слишком близко к телу (%.2f м)" % fr)
	else:
		print("  → снаряд выйдет из ВЫБРОШЕННОЙ ВПЕРЁД правой кисти (%.2f м)" % fr)

	if fails.is_empty():
		print("")
		print("FIREBALL: ALL PASS")
		quit(0)
	else:
		print("")
		print("FIREBALL FAIL: ", "; ".join(fails))
		quit(1)

func _spawn_delay_of(skill) -> float:
	for e in skill.effects:
		if "spawn_delay" in e:
			return float(e.spawn_delay)
	return 0.0

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
