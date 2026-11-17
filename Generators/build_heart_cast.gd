extends SceneTree
## Сердечки (вердикт 17.11.26): insta-каст = Cast_Enter + Cast_Exit (левая
## рука) склеенные в Heart_Cast + зеркальная Heart_Cast_L (правая рука).
## Зеркало ИЕРАРХИЧЕСКОЕ по глобальным позам (M·W·M) — наивная конъюгация
## локалов на mixamo ломала риг (коммит 49d1088: 176.71° на RightShoulder):
##   G'[partner(b)] = M · G[b] · M,  M = diag(-1,1,1) (сагиттальная плоскость)
##   локалы: L' = G'[parent]⁻¹ · G'; ротации → треки.
## Транслеции НЕ-Hips костей в клип не пишем: они берутся из rest (симметрия
## рига проверяется ассертом-дрифтом) — игра обнуляет x/z ВСЕМ позиционным
## трекам (PlayerAnimationComponent), рука с позиционным треком сломается.
## Позиционный трек остаётся только у Hips (его x/z игра всё равно гасит).
##
## Запуск: --headless -s res://Generators/build_heart_cast.gd
## Цепочка сборки библиотеки: retarget_ual_anims.gd → build_heart_cast.gd

const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const ENTER := "Cast_Enter"
const EXIT := "Cast_Exit"
const M_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load(LIB_PATH)
	if lib == null or not (lib is AnimationLibrary):
		print("HEART FAIL: нет библиотеки ", LIB_PATH)
		quit(1)
		return
	var enter: Animation = lib.get_animation(ENTER)
	var exit_a: Animation = lib.get_animation(EXIT)
	if enter == null or exit_a == null:
		print("HEART FAIL: нет исходных клипов ", ENTER, "/", EXIT)
		quit(1)
		return

	var heart := _concat(enter, exit_a)
	heart.resource_name = "Heart_Cast"
	print("HEART склейка: len=%.3f tracks=%d" % [heart.length, heart.get_track_count()])

	# Скелет скина: rest-иерархия для глобальных поз и проверки симметрии.
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var skel: Skeleton3D = _find_skeleton(player)
	if skel == null:
		print("HEART FAIL: нет Skeleton3D в ", PLAYER_SCENE)
		quit(1)
		return

	var seam := _seam_report(enter, exit_a)
	print("HEART шов Enter→Exit: max=%.1f° avg=%.1f°" % [seam[0], seam[1]])

	var heart_l := _mirror(heart, skel)
	if heart_l == null:
		quit(1)
		return
	heart_l.resource_name = "Heart_Cast_L"

	if lib.has_animation("Heart_Cast"):
		lib.remove_animation("Heart_Cast")
	if lib.has_animation("Heart_Cast_L"):
		lib.remove_animation("Heart_Cast_L")
	lib.add_animation("Heart_Cast", heart)
	lib.add_animation("Heart_Cast_L", heart_l)
	var err := ResourceSaver.save(lib, LIB_PATH)
	print("HEART SAVE err=%d clips=%d" % [err, lib.get_animation_list().size()])
	quit(0 if err == OK else 1)

## Склейка: треки A как есть, треки B теми же путями со сдвигом на A.length.
func _concat(a: Animation, b: Animation) -> Animation:
	var out := Animation.new()
	out.loop_mode = Animation.LOOP_NONE
	out.length = a.length + b.length
	for i in a.get_track_count():
		var t := a.track_get_type(i)
		var ni := out.add_track(t)
		out.track_set_path(ni, a.track_get_path(i))
		out.track_set_interpolation_type(ni, a.track_get_interpolation_type(i))
		for k in a.track_get_key_count(i):
			out.track_insert_key(ni, a.track_get_key_time(i, k), a.track_get_key_value(i, k))
	for i in b.get_track_count():
		var t := b.track_get_type(i)
		var path := b.track_get_path(i)
		var ni := _find_track(out, t, path)
		if ni < 0:
			ni = out.add_track(t)
			out.track_set_path(ni, path)
			out.track_set_interpolation_type(ni, b.track_get_interpolation_type(i))
		for k in b.track_get_key_count(i):
			out.track_insert_key(ni, b.track_get_key_time(i, k) + a.length, b.track_get_key_value(i, k))
	return out

func _find_track(a: Animation, type: int, path: NodePath) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == type and a.track_get_path(i) == path:
			return i
	return -1

## Диф поз последнего ключа Enter и первого ключа Exit (плавность шва).
func _seam_report(a: Animation, b: Animation) -> Array:
	var worst := 0.0
	var total := 0.0
	var cnt := 0
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		if a.track_get_key_count(i) == 0:
			continue
		var j := -1
		for jj in b.get_track_count():
			if b.track_get_path(jj) == a.track_get_path(i):
				j = jj
				break
		if j < 0 or b.track_get_key_count(j) == 0:
			continue
		var q1: Quaternion = a.track_get_key_value(i, a.track_get_key_count(i) - 1)
		var q2: Quaternion = b.track_get_key_value(j, 0)
		var ang := absf(q1.angle_to(q2))
		worst = maxf(worst, ang)
		total += ang
		cnt += 1
	return [rad_to_deg(worst), rad_to_deg(total / maxf(cnt, 1))]

## Зеркало: глобалы считаем из rest-транслеций + ротаций треков (ровно так их
## считает Godot), зеркалим в партнёров, локалы → ключи нового клипа.
func _mirror(src: Animation, skel: Skeleton3D) -> Animation:
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
				print("HEART FAIL: нет партнёра для ", n)
				return null
			partner[i] = pi

	var tracks := []
	for i in src.get_track_count():
		var path := String(src.track_get_path(i))
		var c := path.rfind(":")
		var bi := skel.find_bone(path.substr(c + 1))
		if bi < 0:
			print("HEART FAIL: кости нет в скелете: ", path)
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
	var times := tset.keys()
	times.sort()

	var out := Animation.new()
	out.loop_mode = Animation.LOOP_NONE
	out.length = src.length
	var dst := []
	for tr in tracks:
		var ni := out.add_track(tr["type"])
		out.track_set_path(ni, NodePath("%s:%s" % [tr["base"], skel.get_bone_name(tr["partner"])]))
		out.track_set_interpolation_type(ni, Animation.INTERPOLATION_LINEAR)
		dst.append(ni)

	var g_last := []
	var gm_last := []
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
				# Симметрия рига: транслеция обязана совпасть с rest партнёра
				# (кость с позиционным треком — Hips — проверяется сквозным тестом)
				if not pos_over.has(p):
					var drift: float = (loc.origin - skel.get_bone_rest(p).origin).length()
					max_drift = maxf(max_drift, drift)
					if drift > 0.003:
						print("HEART WARN: drift %.4f на %s t=%.3f" % [drift, skel.get_bone_name(p), t])
			elif tr["type"] == Animation.TYPE_POSITION_3D:
				out.track_insert_key(dst[ti], t, loc.origin)
		# 5) Сквозная проверка: готовый out, вычисленный так же, как его считает
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
		g_last = g
		gm_last = gm

	# Контроль смены рук: X кисти должен инвертироваться
	var lh := skel.find_bone("mixamorig_LeftHand")
	var rh := skel.find_bone("mixamorig_RightHand")
	print("HEART контроль зеркала: LeftHand(src) x=%.3f → RightHand(L) x=%.3f" % [g_last[lh].origin.x, gm_last[rh].origin.x])
	print("HEART зеркало: times=%d max_drift=%.5f | сквозная проверка: pos<=%.4f м rot<=%.2f°" % [times.size(), max_drift, max_err_p, rad_to_deg(max_err_r)])
	return out

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null
