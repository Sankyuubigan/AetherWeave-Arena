extends SceneTree
## РЕНДЕР-ПРОВЕРКА СЕРДЕЧКА ЧЕРЕЗ РЕАЛЬНЫЙ ПУТЬ ВОСПРОИЗВЕДЕНИЯ (27.11.26).
##
## Почему переписан: прежний render_heart_check.gd срывал скрипты и крутил
## СЫРОЙ AnimationPlayer библиотеки. Игра же играет каст через
## PlayerAnimationComponent.play_cast_anim → CastAnimationLayer (CastPlayer,
## UB/full-body, capture-блендинг) + AimSpineModifier. Сырой замер расходился
## с игрой на десятки градусов (сыро 87° vs реальный путь 28° на том же t) —
## юзер видел одно, гейт мерил другое.
##
## Ракурсы (проблема «в бок» видна ТОЛЬКО сверху; спереди вынос вперёд
## проецируется в камеру и не читается):
##   side  — камера сбоку (x+), видно вынос вперёд по оси Z;
##   top   — камера сверху, видно БОКОВОЕ отклонение кистей (главный ракурс);
##   front — камера спереди, контроль позы.
##
## Запуск (нужно окно — headless не рендерит):
##   powershell -NoProfile -ExecutionPolicy Bypass -File _tmp_probe/run_heart_real.ps1
## Выход: _tmp_probe/hr_<clip>_<t>_<view>.png + строки HR t=... R=(x,z) ang=...

const PLAYER_SCENE := "res://Scenes/player.tscn"
const OUT_DIR := "res://_tmp_probe"
## Кадры — в координатах КЛИПА (темп 2.0: спавн 0.33 с реального = t 0.66).
const CLIPS := {
	"Cast_1H_Magic_02": [0.44, 0.66, 0.88],
	"Cast_1H_Magic_02_L": [0.44, 0.66, 0.88],
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_position(Vector2i(-2400, -2400))
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	# Скин должен стоять на полу и НЕ бежать: play_cast_anim выбирает
	# full-body только при hs<0.2 && is_on_floor. Даём физике осесть.
	for i in 30:
		await physics_frame
	player.rotation.y = 0.0
	# Модель Mixamo смотрит в +Z при yaw 0 (docs/cast_pipeline.md §7).
	# Камера в игре стоит СЗАДИ и смотрит в −Z ⇒ wrapper.yaw = π, как в
	# probe_heart_pick (иначе мерим/рисуем зеркально).
	var wrapper: Node3D = player.get_node_or_null("GraphicsWrapper")
	if wrapper:
		wrapper.rotation.y = PI
	var skel := _skel(player)
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if skel == null or comp == null:
		print("HR FAIL: нет скелета/PlayerAnimationComponent")
		quit(1)
		return
	var ri := skel.find_bone("mixamorig_RightHand")
	var li := skel.find_bone("mixamorig_LeftHand")
	var ci := skel.find_bone("mixamorig_Spine2")

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-40, 150, 0)
	sun2.light_energy = 0.5
	root.add_child(sun2)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)

	# Модель смотрит в +Z ⇒ «вперёд» = +Z. Камеры:
	#   top   — сверху, +Z вверх кадра: боковое отклонение кистей видно как
	#           горизонтальный сдвиг (ГЛАВНЫЙ ракурс для «в бок»);
	#   side  — справа (x+), видно, вынесена ли рука ВПЕРЁД по Z;
	#   front — спереди (+Z), контроль.
	var views := {
		"top": [Vector3(0.0, 4.2, 0.05), Vector3(0, 1.15, 0)],
		"side": [Vector3(4.0, 1.5, 0.2), Vector3(0, 1.15, 0.1)],
		"front": [Vector3(0.0, 1.5, 4.0), Vector3(0, 1.15, 0)],
	}
	for clip in CLIPS:
		for t in CLIPS[clip]:
			# Реальный путь: play_cast_anim (full-body при стоянии) + seek.
			# Время — ТОЛЬКО seek: счётчик 1/FPS в headless не двигает клип
			# (дельта кадра ≠ 1/30), кадры выходили из начала клипа.
			comp.play_cast_anim(clip)
			var len: float = comp.cast_last_len()
			comp.cast_player.seek(clampf(float(t), 0.0, len), true)
			skel.force_update_all_bone_transforms()
			var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(ci).origin
			var pr: Vector3 = skel.global_transform * skel.get_bone_global_pose(ri).origin
			var pl: Vector3 = skel.global_transform * skel.get_bone_global_pose(li).origin
			var dr: Vector3 = pr - c
			var dl: Vector3 = pl - c
			dr.y = 0.0
			dl.y = 0.0
			# forward в мире = −Z (камера игрока смотрит в −Z), кисть впереди,
			# если её проекция по −Z положительна ⇒ fwd = −d.z.
			var fr: float = -dr.z
			var fl: float = -dl.z
			print("HR %-14s t=%.2f/%.2f R(x=%+.2f fwd=%+.2f ang=%.0f°) L(x=%+.2f fwd=%+.2f ang=%.0f°)" % [
				clip, float(t), len, dr.x, fr,
				rad_to_deg(atan2(absf(dr.x), maxf(fr, 0.001))),
				dl.x, fl, rad_to_deg(atan2(absf(dl.x), maxf(fl, 0.001)))])
			for vname in views:
				var v: Array = views[vname]
				cam.look_at_from_position(v[0], v[1], Vector3.UP if vname != "top" else Vector3(0, 0, 1))
				cam.make_current()
				await process_frame
				await process_frame
				var img := root.get_texture().get_image()
				img.save_png("%s/hr_%s_%.2f_%s.png" % [OUT_DIR, clip.to_lower(), float(t), vname])
	print("HR RENDER DONE")
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
	var floor_node := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_node.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.35, 0.4)
	floor_node.material_override = fmat
	root.add_child(floor_node)

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skel(c)
		if r != null:
			return r
	return null
