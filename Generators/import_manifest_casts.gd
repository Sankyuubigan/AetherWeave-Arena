extends SceneTree
## ИМПОРТЁР КАСТОВ ИЗ МАНИФЕСТА (26.11.26, v2 — на едином модуле ретаргета).
##
## Берёт записи `Data/animations_manifest.json` (ССОТ) со `source: mixamo://…`
## и `layer: cast`, грузит FBX, ретаргетит на скин игрока через
## `Generators/anim_retarget_lib.gd` и кладёт клип в каст-библиотеку под именем
## `name` из манифеста (+ `<name>_L` иерархическим зеркалом при `mirror: true`).
##
## ИСТОРИЯ (не повторять): до 26.11.26 здесь был `_to_lib_shape()` — он клал
## СЫРЫЕ локальные кватернионы FBX на скин с другой rest-позой, комментарий
## обещал компенсацию, которой в коде не было. Итог: сердечко вытягивало руки
## в стороны (side=+0.74 вместо fwd=+0.74 на родном FBX), искажены были
## Cast_1H_Magic_02, Cast_2H_Area_01, Tether_Swing, Cast_2H_Spell. Теперь вся
## математика — в anim_retarget_lib.gd (одно место), здесь только IO.
##
## ДВА КАТАЛОГА ИСТОЧНИКОВ (порядок важен): сначала `Graphics/Animations/raw/
## mixamo/` (рабочая папка), затем `Graphics/mixamo-lib/fbx/` (оффлайн-библиотека
## Mixamo, docs/mixamo_library.md). В библиотеке лежат клипы, которых нет в raw:
## Dismissing_Gesture, Dismissing_Gesture_2, Guitar_Playing, Guitar_Playing_2,
## Magic_Heal.
##
## Идемпотентно. Цепочка: retarget_ual_anims.gd → ЭТОТ → build_cast_fb.gd →
## build_cast_ub.gd → build_heart_cast.gd (легаси Heart_Cast, не перетирается).
## Запуск: --headless -s res://Generators/import_manifest_casts.gd

const MANIFEST := "res://Data/animations_manifest.json"
const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const MIXAMO_DIRS := [
	"res://Graphics/Animations/raw/mixamo/",
	"res://Graphics/mixamo-lib/fbx/",
]
const RETARGET = preload("res://Generators/anim_retarget_lib.gd")
const MIRROR_LIB = preload("res://Generators/mirror_lib_anim.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY or not data.has("entries"):
		print("IMP FAIL: битый манифест ", MANIFEST)
		quit(1)
		return
	var lib: AnimationLibrary = load(LIB_PATH)
	if lib == null:
		print("IMP FAIL: нет библиотеки ", LIB_PATH)
		quit(1)
		return
	var skel := await _load_skin_skeleton()
	if skel == null:
		print("IMP FAIL: нет скелета в ", PLAYER_SCENE)
		quit(1)
		return

	var done := 0
	var failed := 0
	var skipped := 0
	for e in data["entries"]:
		if not (e is Dictionary):
			continue
		var src: String = str(e.get("source", ""))
		if not src.begins_with("mixamo://") or str(e.get("layer", "")) != "cast":
			continue
		var name: String = str(e.get("name", ""))
		if name.is_empty():
			continue
		var fname: String = src.substr(9)
		var fbx := _find_fbx(fname)
		if fbx == "":
			# Отсутствие файла — не провал сборки: часть манифеста может
			# описывать клипы, которые юзер ещё не скачал. Печатаем громко.
			print("IMP SKIP %s: нет FBX %s ни в одном каталоге" % [name, fname])
			skipped += 1
			continue
		var fbx_scene := _load_fbx(fbx)
		if fbx_scene.is_empty():
			print("IMP FAIL %s: FBX не загрузился (%s)" % [name, fbx])
			failed += 1
			continue
		var clip := RETARGET.retarget(fbx_scene["anim"], fbx_scene["skel"], skel, "IMP " + name)
		var fbx_skel: Skeleton3D = fbx_scene["skel"]
		_free_fbx(fbx_scene)
		if clip == null:
			print("IMP FAIL %s: ретаргет не собрался (%s)" % [name, fbx])
			failed += 1
			continue
		clip.resource_name = name
		clip.loop_mode = Animation.LOOP_LINEAR if bool(e.get("loop", false)) else Animation.LOOP_NONE
		if bool(e.get("reverse", false)):
			# Телепорт (решение юзера 26.11.26): появление = РЕВЕРС жеста
			# исчезновения, запечённый в данные (не рантайм speed_scale —
			# отрицательный темп ломает окно отмены и IK-доводку).
			var rev := _reverse(clip)
			rev.resource_name = name
			rev.loop_mode = clip.loop_mode
			clip = rev
		_put(lib, name, clip)
		var msg := "  %-16s %.2fс треков=%d %s" % [
			name, clip.length, clip.get_track_count(),
			"loop" if clip.loop_mode != Animation.LOOP_NONE else ""]
		done += 1
		if bool(e.get("mirror", false)):
			var ml: Animation = MIRROR_LIB.mirror(clip, skel, "IMP-MIRROR " + name)
			if ml == null:
				print("IMP FAIL %s: зеркало не собралось" % name)
				failed += 1
				continue
			ml.resource_name = name + "_L"
			ml.loop_mode = clip.loop_mode
			_put(lib, name + "_L", ml)
			msg += " + _L"
		print(msg)

	var err := ResourceSaver.save(lib, LIB_PATH)
	print("IMP SAVE err=%d импортировано=%d провалов=%d пропущено(нет файла)=%d всего_клипов=%d" % [
		err, done, failed, skipped, lib.get_animation_list().size()])
	quit(0 if err == OK and failed == 0 else 1)

## Поиск FBX по имени файла в каталогах-источниках (порядок = приоритет).
func _find_fbx(fname: String) -> String:
	for d in MIXAMO_DIRS:
		var p: String = String(d) + fname
		if FileAccess.file_exists(p):
			return p
	return ""

## FBX → {"anim", "skel", "scene"}. Пустой словарь = не загрузился.
## Сцена НЕ освобождается здесь: скелет нужен живым для ретаргета
## (rest-иерархия), освобождает вызывающий через _free_fbx().
func _load_fbx(path: String) -> Dictionary:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err := doc.append_from_file(path, state)
	if err != OK:
		print("IMP: FBXDocument error %s (%s)" % [error_string(err), path])
		return {}
	var scene := doc.generate_scene(state)
	if scene == null:
		return {}
	root.add_child(scene)
	var skel := _find_skel(scene)
	var ap := _find_ap(scene)
	if skel == null or ap == null:
		root.remove_child(scene)
		scene.free()
		return {}
	var flib := ap.get_animation_library("")
	if flib == null or flib.get_animation_list().is_empty():
		root.remove_child(scene)
		scene.free()
		return {}
	var clip: Animation = flib.get_animation(flib.get_animation_list()[0])
	return {"anim": clip, "skel": skel, "scene": scene}

func _free_fbx(d: Dictionary) -> void:
	var sc: Node = d["scene"]
	root.remove_child(sc)
	sc.free()

func _put(lib: AnimationLibrary, name: String, clip: Animation) -> void:
	if lib.has_animation(name):
		lib.remove_animation(name)
	lib.add_animation(name, clip)

## Реверс клипа: t' = length − t, порядок ключей переворачивается. Кватернионы
## НЕ инвертируются (это не обратная анимация, а проигрывание назад) —
## гемиспера применяется заново, потому что обратный порядок меняет «предыдущий»
## ключ и без неё интерполяция пойдёт длинной дугой.
func _reverse(src: Animation) -> Animation:
	var out := Animation.new()
	out.length = src.length
	for i in src.get_track_count():
		var t := src.track_get_type(i)
		var ni := out.add_track(t)
		out.track_set_path(ni, src.track_get_path(i))
		out.track_set_interpolation_type(ni, src.track_get_interpolation_type(i))
		var kc := src.track_get_key_count(i)
		for k in kc:
			var nt: float = src.length - src.track_get_key_time(i, kc - 1 - k)
			out.track_insert_key(ni, nt, src.track_get_key_value(i, kc - 1 - k))
	return out

func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null

## Скелет скина (rest-иерархия) из player.tscn; скрипты срезаем — сцена должна
## грузиться без логики (тот же приём, что в build_cast_ub.gd).
func _load_skin_skeleton() -> Skeleton3D:
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		return null
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	return _find_skel(player)

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
