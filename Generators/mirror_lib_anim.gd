extends RefCounted
## Иерархическое зеркало клипа по глобальным позам — вынесено из
## build_heart_cast.gd (26.11.26), чтобы зеркалить и манимо-импортированные
## касты (import_manifest_casts.gd). Рецепт — §13.1 docs/animation_generation.md.
##
## Наивная конъюгация ЛОКАЛОВ ломает mixamo-риг (коммит 49d1088: 176.71° на
## RightShoulder): локальная ось сгиба у левой и правой кости разная. Поэтому
## считаем ГЛОБАЛЫ кадра (rest-транслеции + ротации треков — ровно как их
## считает Godot), зеркалим их в партнёрские кости и только потом возвращаемся
## в локалы. M = diag(−1,1,1) — сагиттальная плоскость.
##
## В клип пишутся ТОЛЬКО ротации (+ позиция кости с позиционным треком, у нас
## это только Hips): транслеции прочих костей берутся из rest — игра обнуляет
## x/z ВСЕМ позиционным трекам (PlayerAnimationComponent).

const M_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const DRIFT_WARN := 0.003   # допуск асимметрии rest (метры)

## Зеркало клипа. src — треки на костях скина (пути вида "<base>:<bone>"),
## skel — скелет скина (нужен для rest-иерархии и пар костей Left↔Right).
## null = ошибка (см. print; вызывающий обязан упасть, а не писать мусор).
static func mirror(src: Animation, skel: Skeleton3D, tag: String = "MIRROR") -> Animation:
	if src == null or skel == null:
		print("%s FAIL: src/skel null" % tag)
		return null
	var nb := skel.get_bone_count()
	var partner := PackedInt32Array()
	partner.resize(nb)
	for i in nb:
		var n := String(skel.get_bone_name(i))
		var s := n.replace("Left", "\u0001").replace("Right", "Left").replace("\u0001", "Right")
		if s == n:
			partner[i] = i
		else:
			var pi := skel.find_bone(s)
			if pi < 0:
				print("%s FAIL: нет партнёра для %s" % [tag, n])
				return null
			partner[i] = pi

	var tracks := []
	for i in src.get_track_count():
		var path := String(src.track_get_path(i))
		var c := path.rfind(":")
		var bi := skel.find_bone(path.substr(c + 1))
		if bi < 0:
			print("%s FAIL: кости нет в скелете: %s" % [tag, path])
			return null
		tracks.append({
			"type": src.track_get_type(i),
			"base": path.substr(0, c),
			"bone": bi,
			"partner": partner[bi],
		})

	var tset := {}
	for i in src.get_track_count():
		for k in src.track_get_key_count(i):
			tset[src.track_get_key_time(i, k)] = true
	var times: Array = tset.keys()
	times.sort()

	var out := Animation.new()
	out.loop_mode = src.loop_mode
	out.length = src.length
	var dst := []
	for tr in tracks:
		var ni := out.add_track(tr["type"])
		out.track_set_path(ni, NodePath("%s:%s" % [tr["base"], skel.get_bone_name(tr["partner"])]))
		out.track_set_interpolation_type(ni, Animation.INTERPOLATION_LINEAR)
		dst.append(ni)

	var max_drift := 0.0
	var max_err_p := 0.0
	var max_err_r := 0.0
	for t in times:
		# 1) Локалы: rest + треки. Кость с ОБОИМИ треками (Hips) — merge, не
		# замена: «последний трек wins» стирал ротацию Hips позиционным треком!
		var rot_over := {}
		var pos_over := {}
		for ti in tracks.size():
			var tr: Dictionary = tracks[ti]
			var bi: int = tr["bone"]
			if tr["type"] == Animation.TYPE_ROTATION_3D:
				rot_over[bi] = src.rotation_track_interpolate(ti, t)
			elif tr["type"] == Animation.TYPE_POSITION_3D:
				pos_over[bi] = src.position_track_interpolate(ti, t)
		var locals := []
		locals.resize(nb)
		for i in nb:
			var l: Transform3D = skel.get_bone_rest(i)
			if rot_over.has(i):
				l.basis = Basis(rot_over[i])
			if pos_over.has(i):
				l.origin = pos_over[i]
			locals[i] = l
		# 2) Глобалы (родители идут раньше детей в индексах Godot)
		var g := []
		g.resize(nb)
		for i in nb:
			var par := skel.get_bone_parent(i)
			g[i] = g[par] * locals[i] if par >= 0 else locals[i]
		# 3) Зеркальные глобалы в партнёров
		var gm := []
		gm.resize(nb)
		for i in nb:
			var x: Transform3D = g[i]
			gm[partner[i]] = Transform3D(M_BASIS * x.basis * M_BASIS, M_BASIS * x.origin)
		# 4) Локалы зеркала → ключи
		for ti in tracks.size():
			var tr: Dictionary = tracks[ti]
			var p: int = tr["partner"]
			var par := skel.get_bone_parent(p)
			var loc: Transform3D = gm[par].affine_inverse() * gm[p] if par >= 0 else gm[p]
			if tr["type"] == Animation.TYPE_ROTATION_3D:
				out.track_insert_key(dst[ti], t, loc.basis.get_rotation_quaternion())
				if not pos_over.has(p):
					var drift: float = (loc.origin - skel.get_bone_rest(p).origin).length()
					max_drift = maxf(max_drift, drift)
					if drift > DRIFT_WARN:
						print("%s WARN: drift %.4f на %s t=%.3f" % [tag, drift, skel.get_bone_name(p), t])
			elif tr["type"] == Animation.TYPE_POSITION_3D:
				out.track_insert_key(dst[ti], t, loc.origin)
		# 5) Сквозная проверка: готовый out, пересчитанный так же, как его считает
		# Godot, обязан дать ровно зеркальные глобалы gm (ловит дыры в матеме).
		var rot2 := {}
		var pos2 := {}
		for ti in tracks.size():
			var tr: Dictionary = tracks[ti]
			var ni: int = dst[ti]
			if tr["type"] == Animation.TYPE_ROTATION_3D:
				rot2[tr["partner"]] = out.rotation_track_interpolate(ni, t)
			elif tr["type"] == Animation.TYPE_POSITION_3D:
				pos2[tr["partner"]] = out.position_track_interpolate(ni, t)
		var lo := []
		lo.resize(nb)
		for i in nb:
			var l2: Transform3D = skel.get_bone_rest(i)
			if rot2.has(i):
				l2.basis = Basis(rot2[i])
			if pos2.has(i):
				l2.origin = pos2[i]
			lo[i] = l2
		var go := []
		go.resize(nb)
		for i in nb:
			var par2 := skel.get_bone_parent(i)
			go[i] = go[par2] * lo[i] if par2 >= 0 else lo[i]
		for i in nb:
			max_err_p = maxf(max_err_p, (go[i].origin - gm[i].origin).length())
			var qa: float = go[i].basis.get_rotation_quaternion().angle_to(gm[i].basis.get_rotation_quaternion())
			max_err_r = maxf(max_err_r, qa)

	print("%s: times=%d max_drift=%.5f | сквозная: pos<=%.4f м rot<=%.2f°" % [
		tag, times.size(), max_drift, max_err_p, rad_to_deg(max_err_r)])
	return out
