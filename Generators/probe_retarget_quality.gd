extends SceneTree
## ГЕЙТ КАЧЕСТВА РЕТАРГЕТА (26.11.26) — обязателен перед коммитом библиотеки.
## PRP: tasks/261126_0838-99d99d09/PRP_импортёр_и_скиллы.md, шаг 3.
##
## ПОЧЕМУ ЭТОТ ГЕЙТ СУЩЕСТВУЕТ: баг сердечка (руки вбок вместо вперёд) жил
## месяцами, потому что НИ ОДНА проверка не мерила РЕЗУЛЬТАТ ретаргета — все
## смотрели на данные клипов (треки есть, ключи есть, длина та же). Дефект был
## в математике, а данные выглядели здоровыми. Гейт обязан мерить то, что видит
## игрок: КУДА УХОДЯТ КИСТИ.
##
## Что делает: для каждой пары (клип библиотеки ↔ FBX-источник из манифеста)
## играет клип на скине игрока и родной FBX на его собственном AnimationPlayer,
## метрика — максимальный вынос кисти от Spine2 по осям (side = |x|, fwd = z).
## Расхождение > TOLERANCE_M по любой оси = FAIL.
##
## Запуск: --headless -s res://Generators/probe_retarget_quality.gd
## EXIT: 0 = все пары сошлись, 1 = есть расхождения (импортёр/ретаргет сломан).

const MANIFEST := "res://Data/animations_manifest.json"
const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const MIXAMO_DIRS := [
	"res://Graphics/Animations/raw/mixamo/",
	"res://Graphics/mixamo-lib/fbx/",
]
## Допуск расхождения кистей, метры. 0.20 — доказанный замером порог
## (temp/probe_global_formula.gd: 10/12 клипов сошлись в пределах 0.09 м).
const TOLERANCE_M := 0.20

var skin: Skeleton3D
var lib: AnimationLibrary
var ap: AnimationPlayer

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	lib = load(LIB_PATH)
	if lib == null:
		print("QUALITY FAIL: нет библиотеки ", LIB_PATH)
		quit(1)
		return
	var player: Node = load(PLAYER_SCENE).instantiate()
	_strip(player)
	root.add_child(player)
	await process_frame
	skin = _find_skel(player)
	if skin == null:
		print("QUALITY FAIL: нет скелета в ", PLAYER_SCENE)
		quit(1)
		return
	ap = AnimationPlayer.new()
	skin.get_parent().add_child(ap)
	ap.root_node = ap.get_path_to(skin.get_parent())
	ap.add_animation_library("", lib)

	var pairs := _manifest_pairs()
	print("клип             | FBX                        | скин П/Л (side,fwd) | FBX П/Л (side,fwd) | дельта | итог")
	print("-----------------|----------------------------|---------------------|--------------------|--------|-----")
	var bad: Array[String] = []
	var checked := 0
	for p in pairs:
		var clip_name: String = p["clip"]
		var fbx_path: String = p["fbx"]
		var skin_m := _measure_lib(clip_name)
		var fbx_m := _measure_fbx(fbx_path)
		if skin_m.is_empty() or fbx_m.is_empty():
			print("%-16s | %-26s | ИЗМЕРЕНИЕ НЕ УДАЛОСЬ (skin=%s fbx=%s)" % [
				clip_name, fbx_path.get_file(), not skin_m.is_empty(), not fbx_m.is_empty()])
			bad.append(clip_name)
			continue
		var d_side: float = maxf(
				absf(float(skin_m["r_side"]) - float(fbx_m["r_side"])),
				absf(float(skin_m["l_side"]) - float(fbx_m["l_side"])))
		var d_fwd: float = maxf(
				absf(float(skin_m["r_fwd"]) - float(fbx_m["r_fwd"])),
				absf(float(skin_m["l_fwd"]) - float(fbx_m["l_fwd"])))
		var ok := d_side <= TOLERANCE_M and d_fwd <= TOLERANCE_M
		checked += 1
		if not ok:
			bad.append(clip_name)
		print("%-16s | %-26s | П%.2f/%+.2f Л%.2f/%+.2f | П%.2f/%+.2f Л%.2f/%+.2f | %.2f/%.2f | %s" % [
			clip_name, fbx_path.get_file(),
			skin_m["r_side"], skin_m["r_fwd"], skin_m["l_side"], skin_m["l_fwd"],
			fbx_m["r_side"], fbx_m["r_fwd"], fbx_m["l_side"], fbx_m["l_fwd"],
			d_side, d_fwd, "OK" if ok else "<<< FAIL (искажение ретаргета)"])

	print("")
	print("QUALITY: проверено %d пар, провалов %d%s" % [
		checked, bad.size(), ("" if bad.is_empty() else " → " + ", ".join(bad))])
	quit(0 if bad.is_empty() else 1)

## Пары «клип библиотеки ↔ FBX» из МАНИФЕСТА (не хардкод): все cast-записи
## с mixamo-источником, у которых клип есть в библиотеке и файл на диске.
## Реверс-клипы пропускаются: они по построению не совпадают с источником.
func _manifest_pairs() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var out: Array = []
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for e in data["entries"]:
		if not (e is Dictionary):
			continue
		var src: String = str(e.get("source", ""))
		if not src.begins_with("mixamo://") or str(e.get("layer", "")) != "cast":
			continue
		if bool(e.get("reverse", false)):
			continue
		var name: String = str(e.get("name", ""))
		if not lib.has_animation(name):
			continue
		var fbx := _find_fbx(src.substr(9))
		if fbx == "":
			continue
		out.append({"clip": name, "fbx": fbx})
	return out

func _find_fbx(fname: String) -> String:
	for d in MIXAMO_DIRS:
		var p: String = String(d) + fname
		if FileAccess.file_exists(p):
			return p
	return ""

## Клип библиотеки на скине игрока.
func _measure_lib(name: String) -> Dictionary:
	ap.stop()
	ap.play(name)
	var a: Animation = lib.get_animation(name)
	return _sweep(a.length, func(t):
		ap.seek(t, true)
		skin.force_update_all_bone_transforms()
		return _hands(skin))

## Родной FBX на ЕГО СОБСТВЕННОМ AnimationPlayer (новый AP с угаданным
## root_node молча не резолвит треки → ложные «не совпало», ловил 26.11.26).
func _measure_fbx(path: String) -> Dictionary:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	if doc.append_from_file(path, state) != OK:
		return {}
	var scene := doc.generate_scene(state)
	if scene == null:
		return {}
	root.add_child(scene)
	var s := _find_skel(scene)
	var fap := _find_ap(scene)
	if s == null or fap == null:
		root.remove_child(scene)
		scene.free()
		return {}
	var flib := fap.get_animation_library("")
	if flib == null or flib.get_animation_list().is_empty():
		root.remove_child(scene)
		scene.free()
		return {}
	var clip_name: String = String(flib.get_animation_list()[0])
	var a: Animation = flib.get_animation(clip_name)
	# Нормализация КОНВЕЙЕРА на стороне источника (26.11.26): build_cast_fb.gd
	# обнуляет yaw таза во всех full-body клипах библиотеки — направлением тела
	# управляет код (face_aim_target), клип не смеет им распоряжаться (у Wings_Fly
	# было −115.8°, персонаж «падал на спину»). Сырой FBX yaw сохраняет, поэтому
	# гейт обязан применить ТУ ЖЕ нормализацию к источнику: иначе он сравнивает
	# повёрнутое с неповёрнутым и даёт 10 ложных FAIL из 18 (поймано 26.11.26).
	_zero_hips_yaw(a)
	fap.play(clip_name)
	var res := _sweep(a.length, func(t):
		fap.seek(t, true)
		s.force_update_all_bone_transforms()
		return _hands(s))
	root.remove_child(scene)
	scene.free()
	return res

## Обнулить yaw таза в клипе — зеркало Generators/build_cast_fb.gd.
## ЕДИНСТВЕННОЕ место нормализации: конвейер (build_cast_fb) и гейт обязаны
## применять ОДНО И ТО ЖЕ, иначе гейт меряет не то, что видит игрок.
func _zero_hips_yaw(a: Animation) -> void:
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(a.track_get_path(i))
		if not (p.ends_with("Hips") or p.ends_with(":Hips")):
			continue
		for k in a.track_get_key_count(i):
			var q: Quaternion = a.track_get_key_value(i, k)
			var e := Basis(q).get_euler()   # YXZ: y = yaw
			e.y = 0.0
			a.track_set_key_value(i, k, Quaternion.from_euler(e))
		return

## Максимальное смещение кистей за клип (шаг 1/30 с) — ОТДЕЛЬНО по каждой руке.
func _sweep(length: float, at: Callable) -> Dictionary:
	var best := {}
	var t := 0.0
	while t <= length + 0.0001:
		var d: Dictionary = at.call(t)
		if not d.is_empty():
			for k in ["r_side", "r_fwd", "l_side", "l_fwd"]:
				var v: float = absf(float(d[k]))
				if not best.has(k) or v > float(best[k]):
					best[k] = v
		t += 1.0 / 30.0
	return best

## Вынос «самой вытянутой» кисти от Spine2: side = |x|, fwd = z.
## Имена костей принимаются в любой нотации — нормализуем через общий модуль.
##
## СМЕЩЕНИЕ кистей ОТ СВОЕЙ REST-ПОЗЫ, в rest-кадре таза: side = |x|, fwd = z.
##
## Почему именно смещение (урок 26.11.26, три итерации метрики):
##  * АБСОЛЮТНЫЕ позиции кистей сравнивать нельзя: rest-позы скина и FBX
##    различаются (у Standing_Idle руки на 14° иначе) — почти статичный idle
##    давал ложные 0.40/0.56 м «искажения»;
##  * МИР нельзя: разные FBX приходят с арматурой, повёрнутой по-своему
##    (тот же Standing_Idle) — оси side/fwd меняются местами, ложный FAIL;
##  * АНИМИРОВАННЫЙ таз нельзя: у 1H-атак тело скручивается, кадр крутится
##    вместе с позой и съедает ровно тот вынос руки, который меряем.
## Смещение от rest в rest-кадре таза инвариантно ко всем трём факторам:
## сравнивается ТО, ЧТО СДЕЛАЛА АНИМАЦИЯ, а не чем rest-позы отличаются.
##
## КАЖДАЯ КИСТЬ ОТДЕЛЬНО (а не «самая вытянутая»): у двуручных клипов максимум
## перескакивает между руками от кадра к кадру, и «самая вытянутая» на скине
## оказывается правой, а на FBX — левой → сравнение разных рук давало ложный
## FAIL (Cast_2H_Spell, Heal_Cast — ловил 26.11.26). Возвращаем обе.
func _hands(s: Skeleton3D) -> Dictionary:
	var si := _bone(s, "Spine2")
	var ri := _bone(s, "RightHand")
	var li := _bone(s, "LeftHand")
	var hi := _bone(s, "Hips")
	if si < 0 or ri < 0 or li < 0:
		return {}
	var gt: Transform3D = s.global_transform
	var frame: Transform3D = (gt * s.get_bone_global_rest(hi)) if hi >= 0 else gt
	var inv := frame.affine_inverse()
	var rest_sp: Vector3 = inv * (gt * s.get_bone_global_rest(si)).origin
	var sp: Vector3 = inv * (gt * s.get_bone_global_pose(si)).origin
	var dr: Vector3 = (inv * (gt * s.get_bone_global_pose(ri)).origin - sp) \
			- (inv * (gt * s.get_bone_global_rest(ri)).origin - rest_sp)
	var dl: Vector3 = (inv * (gt * s.get_bone_global_pose(li)).origin - sp) \
			- (inv * (gt * s.get_bone_global_rest(li)).origin - rest_sp)
	return {
		"r_side": absf(dr.x), "r_fwd": dr.z,
		"l_side": absf(dl.x), "l_fwd": dl.z,
	}

func _bone(s: Skeleton3D, short: String) -> int:
	var i := s.find_bone("mixamorig_" + short)
	if i >= 0:
		return i
	return s.find_bone("mixamorig1_" + short)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null

func _strip(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip(c)
