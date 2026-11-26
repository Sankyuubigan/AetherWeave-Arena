extends SceneTree
## Экспорт СОСТОЯНИЯ АНИМАЦИЙ для админки (26.11.26) → temp/anim_library.json.
## Зачем: страница «Анимации» показывает «имя клипа в игре ↔ файл ↔ есть ли в
## библиотеке», а сервер не умеет читать .res. Дамп пишет Godot, читает Python.
## Что внутри:
##   casts    — клипы каст-библиотеки (ual_casts_test.res): длина, треки, _UB
##   loco     — клипы локомоции (shared_animations.res)
##   manifest — Data/animations_manifest.json по именам (source/layer/loop/status)
##   by_file  — обратный маппинг «файл источника → имена клипов игры»
## Запуск: --headless -s res://Generators/export_anim_library.gd
## Вызывается и admin\start_admin.bat, и probe_admin_anim.gd.

const OUT_PATH := "res://temp/anim_library.json"
const CAST_LIB := "res://Graphics/Animations/ual_casts_test.res"
const LOCO_LIB := "res://Graphics/Animations/shared_animations.res"
const MANIFEST := "res://Data/animations_manifest.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	quit(write_dump(OUT_PATH))


static func write_dump(path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[anim-export] FAIL открыть %s, ошибка %d" % [path, FileAccess.get_open_error()])
		return 1
	f.store_string(JSON.stringify(build_dump(), "\t"))
	f.close()
	print("[anim-export] дамп записан: %s" % path)
	return 0


## Дамп библиотек + манифеста. Вынесено отдельно — тестируется без записи файла.
static func build_dump() -> Dictionary:
	var casts := _lib_info(CAST_LIB)
	var loco := _lib_info(LOCO_LIB)
	var manifest := {}
	var by_file := {}
	var m_txt := FileAccess.get_file_as_string(MANIFEST)
	var m = JSON.parse_string(m_txt)
	if m is Dictionary and m.has("entries"):
		for e in m["entries"]:
			if not (e is Dictionary):
				continue
			var nm := str(e.get("name", ""))
			if nm.is_empty():
				continue
			var src := str(e.get("source", ""))
			manifest[nm] = {
				"source": src,
				"layer": str(e.get("layer", "")),
				"loop": bool(e.get("loop", false)),
				"hand_pose": str(e.get("hand_pose", "")),
				"status": str(e.get("status", "missing")),
			}
			if src.begins_with("mixamo://"):
				var fn := src.substr(9)
				if not by_file.has(fn):
					by_file[fn] = []
				by_file[fn].append(nm)
	return {
		"generated": Time.get_datetime_string_from_system(),
		"casts": casts,
		"loco": loco,
		"manifest": manifest,
		"by_file": by_file,
		"casts_count": casts.size(),
		"loco_count": loco.size(),
	}


## {имя_клипа: {len, tracks, rot, ub}} по библиотеке .res (пустой словарь = нет файла).
static func _lib_info(path: String) -> Dictionary:
	var out := {}
	var lib = load(path)
	if lib == null or not (lib is AnimationLibrary):
		print("[anim-export] WARN: библиотека не читается: %s" % path)
		return out
	for an in lib.get_animation_list():
		var n := String(an)
		var a: Animation = lib.get_animation(an)
		if a == null:
			continue
		var rot := 0
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				rot += 1
		out[n] = {
			"len": snappedf(a.length, 0.01),
			"tracks": a.get_track_count(),
			"rot": rot,
			"keys": a.track_get_key_count(0) if a.get_track_count() > 0 else 0,
			"ub": n.ends_with("_UB"),
			"loop": a.loop_mode != Animation.LOOP_NONE,
		}
	return out
