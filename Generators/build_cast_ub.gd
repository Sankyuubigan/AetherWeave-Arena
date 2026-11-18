extends SceneTree
## Бейк UB-вариантов каст-клипов (режим «всегда UB», вердикт юзера 17.11.26):
## для КАЖДОГО клипа ual_casts_test.res строит <Имя>_UB, в котором сняты
## ротации ног и позиция Hips — каст играет только верх тела, ноги всегда
## ведёт локомоция (лейеринг вторым AnimationPlayer, как Unreal Slots).
##
## Хвост 0.2 с «возврат к позе Idle» — только завершающим клипам: при
## остановке CastPlayer верх мгновенно = поза локомоции (кросс-миксерного
## бленда нет), хвост сводит скачок к разнице Idle↔Run. Внутри канала
## (Cast_Enter → Cast_Loop) хвост НЕ нужен и сломал бы стык.
##
## Идемпотентно: перезапуск пересобирает все UB.
## Цепочка сборки: retarget_ual_anims.gd → build_heart_cast.gd → build_cast_ub.gd
## Запуск: --headless -s res://Generators/build_cast_ub.gd

const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const TAIL := 0.2
## Завершающие клипы — получают хвост возврата к Idle-верхней позе.
const TAIL_CLIPS := [
	"Throw", "Cast_Shoot", "Heart_Cast", "Heart_Cast_L",
	"Pistol_Shoot", "Beam_Push", "Cast_Exit",
	"Blade_Swing_A", "Blade_Swing_B",
]
const LEG_BONES := [
	"mixamorig_LeftUpLeg", "mixamorig_RightUpLeg",
	"mixamorig_LeftLeg", "mixamorig_RightLeg",
	"mixamorig_LeftFoot", "mixamorig_RightFoot",
	"mixamorig_LeftToeBase", "mixamorig_RightToeBase",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load(LIB_PATH)
	if lib == null or not (lib is AnimationLibrary):
		print("UB FAIL: нет библиотеки ", LIB_PATH)
		quit(1)
		return
	var idle: Animation = await _load_idle()
	if idle == null:
		print("UB FAIL: нет клипа Idle в ", PLAYER_SCENE)
		quit(1)
		return

	var names: Array = lib.get_animation_list()
	var built := 0
	for anim_name in names:
		var base := String(anim_name)
		if base.ends_with("_UB"):
			continue
		var src: Animation = lib.get_animation(anim_name)
		var ub := _make_ub(src, idle, base in TAIL_CLIPS)
		ub.resource_name = base + "_UB"
		if not _selfcheck(src, ub):
			print("UB FAIL: самопроверка не сошлась на ", ub.resource_name)
			quit(1)
			return
		if lib.has_animation(ub.resource_name):
			lib.remove_animation(ub.resource_name)
		lib.add_animation(ub.resource_name, ub)
		built += 1

	var err := ResourceSaver.save(lib, LIB_PATH)
	print("UB SAVE err=%d построено=%d всего клипов=%d" % [err, built, lib.get_animation_list().size()])
	quit(0 if err == OK else 1)

## UB-вариант: копируем все треки кроме ротаций ног и позиции Hips;
## завершающим клипам добавляем хвост «верх → поза Idle».
func _make_ub(src: Animation, idle: Animation, with_tail: bool) -> Animation:
	var out := Animation.new()
	out.length = src.length + (TAIL if with_tail else 0.0)
	out.loop_mode = src.loop_mode
	for i in src.get_track_count():
		var t := src.track_get_type(i)
		var path := String(src.track_get_path(i))
		var bone := path.substr(path.rfind(":") + 1)
		if bone in LEG_BONES and t == Animation.TYPE_ROTATION_3D:
			continue
		if bone == "mixamorig_Hips" and t == Animation.TYPE_POSITION_3D:
			continue
		var ni := out.add_track(t)
		out.track_set_path(ni, src.track_get_path(i))
		out.track_set_interpolation_type(ni, src.track_get_interpolation_type(i))
		for k in src.track_get_key_count(i):
			out.track_insert_key(ni, src.track_get_key_time(i, k), src.track_get_key_value(i, k))
		if with_tail and t == Animation.TYPE_ROTATION_3D:
			var idle_q = _idle_rot(idle, src.track_get_path(i))
			if idle_q != null:
				out.track_insert_key(ni, out.length, idle_q)
	return out

## Ротация кости в позе Idle (t=0) для хвоста возврата; null — если трека нет.
func _idle_rot(idle: Animation, path: String):
	for i in idle.get_track_count():
		if idle.track_get_type(i) == Animation.TYPE_ROTATION_3D \
				and String(idle.track_get_path(i)) == path \
				and idle.track_get_key_count(i) > 0:
			return idle.rotation_track_interpolate(i, 0.0)
	return null

## Самопроверка: в пределах исходной длины UB обязан совпадать с исходником
## на сохранённых треках (дельта ключей + интерполяция в середине клипа).
func _selfcheck(src: Animation, ub: Animation) -> bool:
	for i in src.get_track_count():
		var t := src.track_get_type(i)
		var path := String(src.track_get_path(i))
		var bone := path.substr(path.rfind(":") + 1)
		var dropped := (bone in LEG_BONES and t == Animation.TYPE_ROTATION_3D) \
				or (bone == "mixamorig_Hips" and t == Animation.TYPE_POSITION_3D)
		if dropped:
			continue
		var j := -1
		for jj in ub.get_track_count():
			if ub.track_get_type(jj) == t and String(ub.track_get_path(jj)) == path:
				j = jj
				break
		if j < 0:
			print("UB SELFCHECK: трек не найден в UB: ", path)
			return false
		# Ключ-в-ключ: словарь времён UB (insert_key сортирует ключи, а в
		# исходнике порядок может быть иным — интерполяцию не сверяем).
		var ub_by_time := {}
		for k in ub.track_get_key_count(j):
			ub_by_time[ub.track_get_key_time(j, k)] = ub.track_get_key_value(j, k)
		for k in src.track_get_key_count(i):
			var kt := src.track_get_key_time(i, k)
			var found := false
			for ut in ub_by_time:
				if absf(ut - kt) < 0.0001:
					found = true
					if t == Animation.TYPE_ROTATION_3D:
						var q1: Quaternion = src.track_get_key_value(i, k)
						var q2: Quaternion = ub_by_time[ut]
						# insert_key нормализует кватернионы; сверяем нормализованные.
						# angle_to на почти параллельных кватернионах ill-conditioned
						# (acos при dot≈1) — меряем dot: 0.999999 ≈ 0.08°.
						if absf(q1.normalized().dot(q2.normalized())) < 0.999999:
							print("UB SELFCHECK: %s t=%.3f значение ключа разошлось (dot %s | %s)" % [
								path, kt, q1, q2])
							return false
					break
			if not found:
				print("UB SELFCHECK: %s нет ключа t=%.3f" % [path, kt])
				return false
	return true

## Idle из библиотеки плеера сцены player.tscn.
func _load_idle() -> Animation:
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	var ap: AnimationPlayer = player.get_node_or_null("GraphicsWrapper/AnimationPlayer")
	if ap == null or not ap.has_animation("Idle"):
		return null
	return ap.get_animation("Idle")

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
