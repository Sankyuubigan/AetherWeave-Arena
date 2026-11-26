extends RefCounted
## ЕДИНСТВЕННЫЙ МОДУЛЬ РЕТАРГЕТА «чужой FBX → наш скин» (26.11.26).
## PRP: tasks/261126_0838-99d99d09/PRP_импортёр_и_скиллы.md, шаг 1.
##
## КОНТРАКТ (нарушать нельзя): вся математика «клип из Mixamo-FBX на наш скин»
## живёт ТОЛЬКО здесь. Импортёры вызывают retarget() и не считают кватернионы
## сами. Иначе снова разъедется математика — именно так родился баг сердечка
## (26.11.26): import_manifest_casts.gd клал СЫРЫЕ локальные кватернионы FBX на
## скин с другой rest-позой, и рука уходила вбок (side=+0.74) вместо вперёд
## (fwd=+0.74 на родном FBX).
##
## ФОРМУЛА (доказана замером temp/probe_global_formula.gd: 10/12 клипов
## совпали с родным FBX в пределах 0.09 м):
##     G_skin(t)       = G_fbx(t) · G_fbx_rest⁻¹ · G_skin_rest
##     local_out(bone) = G_skin(parent)⁻¹ · G_skin(bone)
## Почему не другие формулы:
##  * локальная rest-дельта из admin/anim_retarget.js (rest_skin·rest_fbx⁻¹·q) —
##    4/10: не учитывает накопление родительских дельт по иерархии;
##  * формула v4 из retarget_ual_anims.gd (S·(A·gT⁻¹)·S⁻¹·mix_rest) — 0/10 на
##    Mixamo: она для UAL-манекена с чужим фреймом S=rotX(−90°), у Mixamo
##    фрейм FBX-арматуры и скина совпадает (Δrot=0, замер probe_fbx_rest.gd).
##
## Что НЕ переносится:
##  * позиции ВСЕХ костей, включая Hips: FBX в сантиметрах, скин в метрах
##    (docs/mixamo_library.md); касты in-place, высота — из rest-иерархии.
##  * масштабы и видимость.
## Переносятся ТОЛЬКО ротации (инвариант UB-бейка: «в UB только ротации»).

const HEMI = preload("res://Generators/anim_quat_hemisphere.gd")
## Минимум сматчившихся костей. Меньше — значит имена не сошлись (mixamorig1_
## vs mixamorig: и т.п.) и результат будет мусором; обязан быть null, не клип.
const MIN_MATCHED := 10

## Нормализация имени кости: mixamorig1_Hips / mixamorig1:Hips / mixamorig:Hips
## → mixamorig_Hips. Имена без префикса Mixamo возвращаются как есть.
static func normalize_bone(name: String) -> String:
	var n := name.strip_edges()
	if n.begins_with("mixamorig1"):
		n = "mixamorig" + n.substr(10)        # mixamorig1_Hips → mixamorig_Hips
	if n.begins_with("mixamorig:"):
		n = "mixamorig_" + n.substr(11)       # Blender-GLB: mixamorig:Hips
	return n

## Ретаргет клипа. src — анимация FBX (локальные ротации, любые имена костей),
## fbx_skel — скелет ТОГО ЖЕ FBX (нужен живым: rest-иерархия), skin_skel —
## скелет скина игрока (rest-иерархия получателя).
## Возвращает новый Animation с путями "Skeleton3D:<кость скина>" или null,
## если сматчилось < MIN_MATCHED костей (fail loud — вызывающий обязан упасть).
static func retarget(src: Animation, fbx_skel: Skeleton3D, skin_skel: Skeleton3D,
		tag: String = "RETARGET") -> Animation:
	if src == null or fbx_skel == null or skin_skel == null:
		print("%s FAIL: нет клипа или скелета (src=%s fbx=%s skin=%s)" % [
			tag, src != null, fbx_skel != null, skin_skel != null])
		return null
	var n_fbx := fbx_skel.get_bone_count()
	var n_skin := skin_skel.get_bone_count()

	# 1) Пары костей по НОРМАЛИЗОВАННОМУ имени (единственное место сопоставления).
	var fbx_by_norm := {}
	for fi in n_fbx:
		fbx_by_norm[normalize_bone(String(fbx_skel.get_bone_name(fi)))] = fi
	var pairs: Array = []       # [{s, f, n, real}]  n — нормаль, real — имя скина
	var unmatched := 0
	for si in n_skin:
		var real := String(skin_skel.get_bone_name(si))
		var n := normalize_bone(real)
		if fbx_by_norm.has(n):
			pairs.append({"s": si, "f": fbx_by_norm[n], "n": n, "real": real})
		else:
			unmatched += 1
	if pairs.size() < MIN_MATCHED:
		print("%s FAIL: сматчилось костей %d из %d скина (нужно ≥%d) — имена FBX и скина не совпадают"
				% [tag, pairs.size(), n_skin, MIN_MATCHED])
		return null

	# 2) Треки клипа по индексу FBX-кости (только ротации).
	var tr_by_f := {}
	for i in src.get_track_count():
		if src.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var p := src.track_get_path(i)
		if p.get_subname_count() == 0:
			continue
		var bn := normalize_bone(String(p.get_subname(p.get_subname_count() - 1)))
		if fbx_by_norm.has(bn):
			tr_by_f[fbx_by_norm[bn]] = i
	if tr_by_f.is_empty():
		print("%s FAIL: в клипе нет ни одного ротационного трека на костях FBX" % tag)
		return null

	# 3) Времена ключей — объединение по всем трекам (порядок по возрастанию).
	var tset := {}
	for fi in tr_by_f:
		var ti: int = tr_by_f[fi]
		for k in src.track_get_key_count(ti):
			tset[src.track_get_key_time(ti, k)] = true
	var times: Array = tset.keys()
	times.sort()
	if times.is_empty():
		print("%s FAIL: у треков нет ключей" % tag)
		return null

	# 4) rest-ротации: FBX локальные и глобальные, скин глобальные.
	var rest_f_l := []
	var rest_f_g := []
	rest_f_l.resize(n_fbx)
	rest_f_g.resize(n_fbx)
	for fi in n_fbx:
		rest_f_l[fi] = fbx_skel.get_bone_rest(fi).basis.get_rotation_quaternion()
		rest_f_g[fi] = fbx_skel.get_bone_global_rest(fi).basis.get_rotation_quaternion()
	var rest_s_g := {}   # по нормализованному имени
	var rest_s_l := {}   # по РЕАЛЬНОМУ имени (для гемисперы)
	for p in pairs:
		rest_s_g[p["n"]] = skin_skel.get_bone_global_rest(int(p["s"])).basis.get_rotation_quaternion()
		rest_s_l[String(p["real"])] = skin_skel.get_bone_rest(int(p["s"])).basis.get_rotation_quaternion()

	# 5) Порядок «родители раньше детей»: FBX-кости и пары скина отдельно.
	var f_order: Array = []
	for fi in n_fbx:
		f_order.append(fi)
	f_order.sort_custom(func(a, b): return _depth(fbx_skel, a) < _depth(fbx_skel, b))
	var s_order: Array = pairs.duplicate()
	s_order.sort_custom(func(a, b): return _depth(skin_skel, int(a["s"])) < _depth(skin_skel, int(b["s"])))
	# Родитель пары: имя (если сматчился) + его rest-глобал на случай, когда
	# родитель в пары НЕ попал (тогда он остаётся в rest — локал считаем от него,
	# а не как от корня, иначе кость «оторвётся» от иерархии).
	for p in s_order:
		var pi := skin_skel.get_bone_parent(int(p["s"]))
		p["pn"] = normalize_bone(String(skin_skel.get_bone_name(pi))) if pi >= 0 else ""
		p["pg"] = (skin_skel.get_bone_global_rest(pi).basis.get_rotation_quaternion()
				if pi >= 0 else Quaternion.IDENTITY)

	# 6) Треки результата — по реальным именам костей скина.
	var out := Animation.new()
	out.length = src.length
	var ot := {}
	for p in pairs:
		var ni := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(ni, NodePath("Skeleton3D:" + String(p["real"])))
		out.track_set_interpolation_type(ni, Animation.INTERPOLATION_LINEAR)
		ot[p["n"]] = ni

	# 7) Кадры: локалы FBX → глобалы FBX → глобалы скина → локалы скина.
	for t in times:
		var loc_f := []
		loc_f.resize(n_fbx)
		for fi in n_fbx:
			loc_f[fi] = (src.rotation_track_interpolate(tr_by_f[fi], t)
					if tr_by_f.has(fi) else rest_f_l[fi])
		var g_f := {}
		for fi in f_order:
			var q: Quaternion = loc_f[fi]
			var pi := fbx_skel.get_bone_parent(fi)
			if pi >= 0 and g_f.has(pi):
				q = (g_f[pi] as Quaternion) * q
			g_f[fi] = q.normalized()
		var g_s := {}
		for p in pairs:
			var f: int = p["f"]
			var nm: String = p["n"]
			g_s[nm] = ((g_f[f] as Quaternion) * (rest_f_g[f] as Quaternion).inverse()
					* (rest_s_g[nm] as Quaternion)).normalized()
		for p in s_order:
			var nm2: String = p["n"]
			var q2: Quaternion = g_s[nm2]
			var pn: String = p["pn"]
			var parent_g: Quaternion = (g_s[pn] as Quaternion) if (pn != "" and g_s.has(pn)) \
					else (p["pg"] as Quaternion)
			q2 = (parent_g.inverse() * q2).normalized()
			out.track_insert_key(ot[nm2], t, q2)

	# 8) Полусфера: без неё компонентная интерполяция идёт «долгой дугой»
	# (визуально — вывих/перекрут кисти, спец 23.11.26).
	HEMI.apply(out, rest_s_l)
	print("%s: костей %d/%d (вне скелета %d), ключей %d, длина %.2fс" % [
		tag, pairs.size(), n_skin, unmatched, times.size(), out.length])
	return out

static func _depth(s: Skeleton3D, b: int) -> int:
	var d := 0
	var i := b
	while s.get_bone_parent(i) >= 0:
		d += 1
		i = s.get_bone_parent(i)
	return d
