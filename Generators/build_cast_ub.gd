extends SceneTree
const HEMI = preload("res://Generators/anim_quat_hemisphere.gd")
## Бейк UB-вариантов каст-клипов (вердикт спеца 23.11.26):
## для КАЖДОГО клипа ual_casts_test.res строит <Имя>_UB: сняты ротации 8 ног,
## ПОЗИЦИЯ и РОТАЦИЯ Hips — железное правило спеца «Hips НИКОГДА в upper-body»
## (до этого Hips-ротация крутила таз до 56° и уносила ноги, отчёт спецу §7).
## Тазовая дельта переносится в Spine (Hip-to-Spine Transfer) — замах корпуса
## сохраняется, ноги всегда ведёт локомоция.
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
const HIPS := "mixamorig_Hips"
## В UAL-клипах нет mixamorig_Spine — риг Hips → Spine1 → Spine2 → Neck,
## перенос идёт в ближайшую к тазу кость Spine1 (по вердикту спеца «Spine»).
const SPINE := "mixamorig_Spine1"
## Доля тазовой дельты, переносимой в Spine (спец: 70% yaw, 35% pitch/roll,
## итоговый угол жёстко клампится ≤35°).
const YAW_KEEP := 0.7
const PITCH_ROLL_KEEP := 0.35
const MAX_TRANSFER_DEG := 35.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load(LIB_PATH)
	if lib == null or not (lib is AnimationLibrary):
		print("UB FAIL: нет библиотеки ", LIB_PATH)
		quit(1)
		return
	var skin = await _load_skin()
	if skin.is_empty() or skin.idle == null:
		print("UB FAIL: не загрузился player.tscn (Idle/скелет)")
		quit(1)
		return

	var names: Array = lib.get_animation_list()
	var built := 0
	for anim_name in names:
		var base := String(anim_name)
		if base.ends_with("_UB"):
			continue
		var src: Animation = lib.get_animation(anim_name)
		var ub := _make_ub(src, skin, base in TAIL_CLIPS)
		ub.resource_name = base + "_UB"
		if not _selfcheck(src, ub, skin):
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

## UB-вариант: копируем треки кроме ног/Hips; Spine несёт перенесённую тазовую
## дельту; завершающим клипам добавляем хвост «верх → поза Idle».
func _make_ub(src: Animation, skin: Dictionary, with_tail: bool) -> Animation:
	var out := Animation.new()
	out.length = src.length + (TAIL if with_tail else 0.0)
	out.loop_mode = src.loop_mode
	# Hip-to-Spine Transfer УДАЛЁН (23.11.26): перенос таза в Spine1 ломал
	# спину под 90° (Spine1 yaw 100° pitch 65° вместо 12/12 в Full-Body).
	# UB = только верх тела: Hips/ноги стрипаются, Spine остаётся как в клипе.
	for i in src.get_track_count():
		var t := src.track_get_type(i)
		var path := String(src.track_get_path(i))
		var bone := path.substr(path.rfind(":") + 1)
		if bone in LEG_BONES and t == Animation.TYPE_ROTATION_3D:
			continue
		if bone == HIPS:
			continue
		var ni := out.add_track(t)
		out.track_set_path(ni, src.track_get_path(i))
		out.track_set_interpolation_type(ni, src.track_get_interpolation_type(i))
		for k in src.track_get_key_count(i):
			out.track_insert_key(ni, src.track_get_key_time(i, k), src.track_get_key_value(i, k))
		if with_tail and t == Animation.TYPE_ROTATION_3D:
			var idle_q = _idle_rot(skin.idle, src.track_get_path(i))
			if idle_q != null:
				out.track_insert_key(ni, out.length, idle_q)
	HEMI.apply(out)
	return out

## Кламп переноса: 70% yaw / 35% pitch/roll (Euler YXZ), затем общий угол ≤35°.
func _clamp_transfer(delta_q: Quaternion) -> Quaternion:
	var e := Basis(delta_q).get_euler()  # YXZ по умолчанию: y=yaw, x=pitch, z=roll
	e.y *= YAW_KEEP
	e.x *= PITCH_ROLL_KEEP
	e.z *= PITCH_ROLL_KEEP
	var q := Quaternion.from_euler(e)
	var ang := absf(q.get_angle())
	if ang > deg_to_rad(MAX_TRANSFER_DEG):
		q = Quaternion(q.get_axis(), deg_to_rad(MAX_TRANSFER_DEG) * signf(q.get_angle()))
	return q

## Ротация кости в позе Idle (t=0) для хвоста возврата; null — если трека нет.
func _idle_rot(idle: Animation, path: String):
	for i in idle.get_track_count():
		if idle.track_get_type(i) == Animation.TYPE_ROTATION_3D \
				and String(idle.track_get_path(i)) == path \
				and idle.track_get_key_count(i) > 0:
			return idle.rotation_track_interpolate(i, 0.0)
	return null

## Самопроверка: UB не содержит ни одного трека Hips/ног (железное правило);
## Spine = формула переноса с клампом; прочие треки совпадают с исходником
## ключ-в-ключ.
func _selfcheck(src: Animation, ub: Animation, skin: Dictionary) -> bool:
	# 1) В UB нет Hips (pos/rot) и ног (rot) — вообще ни одного трека.
	for i in ub.get_track_count():
		var t0 := ub.track_get_type(i)
		var bone0 := _bone_of(ub.track_get_path(i))
		if bone0 == HIPS:
			print("UB SELFCHECK: Hips-трек просочился в UB: ", bone0)
			return false
		if bone0 in LEG_BONES and t0 == Animation.TYPE_ROTATION_3D:
			print("UB SELFCHECK: нога просочилась в UB: ", bone0)
			return false
	# 2) Spine — копия исходника (Hip-to-Spine transfer удалён 23.11.26).
	# 3) Прочие сохранённые треки — совпадение с исходником ключ-в-ключ.
	for i in src.get_track_count():
		var t := src.track_get_type(i)
		var path := String(src.track_get_path(i))
		var bone := _bone_of(path)
		var dropped := (bone in LEG_BONES and t == Animation.TYPE_ROTATION_3D) \
				or (bone == HIPS)
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

func _key_at(src: Animation, tr: int, t: float) -> Quaternion:
	var k := src.track_find_key(tr, t, Animation.FIND_MODE_NEAREST)
	return src.track_get_key_value(tr, k)

func _bone_of(path) -> String:
	return String(path).substr(String(path).rfind(":") + 1)

func _find_track(a: Animation, bone: String, type: int) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == type and String(a.track_get_path(i)).ends_with(":" + bone):
			return i
	return -1

## Idle и rest-ротация Hips из player.tscn (скрипты сцены срезаны).
func _load_skin() -> Dictionary:
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	var out := {"idle": null, "hips_rest": Quaternion.IDENTITY}
	var ap: AnimationPlayer = player.get_node_or_null("GraphicsWrapper/AnimationPlayer")
	if ap != null and ap.has_animation("Idle"):
		out.idle = ap.get_animation("Idle")
	var skel := _find_skel(player)
	if skel:
		var hb := skel.find_bone(HIPS)
		if hb >= 0:
			out.hips_rest = skel.get_bone_rest(hb).basis.get_rotation_quaternion()
	player.free()
	return out

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skel(c)
		if r:
			return r
	return null

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
