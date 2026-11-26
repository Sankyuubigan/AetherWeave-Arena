extends SceneTree
## Диагностика (26.11.26): какие НЕ-ротационные треки лежат в ual_casts_test.res
## и в каких клипах. Нужно для инварианта гейта test_cast_anims: он сканирует
## ВСЮ библиотеку, а full-body (не-UB) клипы законно несут позицию Hips.
## Запуск: --headless -s res://Generators/probe_lib_tracks.gd

const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load(LIB_PATH)
	var total := 0
	print("=== треки по клипам ", LIB_PATH, " ===")
	for an in lib.get_animation_list():
		var a: Animation = lib.get_animation(an)
		var pos := 0
		var rot := 0
		var names: Array[String] = []
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				rot += 1
			else:
				pos += 1
				names.append("%s" % String(a.track_get_path(i)).split(":")[-1])
		total += pos
		var ub := String(an).ends_with("_UB")
		print("  %-22s rot=%2d nonrot=%2d %s %s" % [
			an, rot, pos, "[UB]" if ub else "[FB]", "" if names.is_empty() else str(names)])
	print("ИТОГО не-ротационных: ", total)
	quit(0)
