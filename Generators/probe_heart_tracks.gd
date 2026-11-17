extends SceneTree
## Структура треков Cast_Enter/Cast_Exit из ual_casts_test.res — база для
## склейки Heart_Cast и зеркала Heart_Cast_L.
## Запуск: --headless -s res://Generators/probe_heart_tracks.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load("res://Graphics/Animations/ual_casts_test.res")
	if lib == null or not lib is AnimationLibrary:
		print("PROBE FAIL: нет библиотеки")
		quit(1)
		return
	for clip_name in ["Cast_Enter", "Cast_Exit"]:
		var a: Animation = lib.get_animation(clip_name)
		print("== %s len=%.3f tracks=%d loop=%d" % [clip_name, a.length, a.get_track_count(), a.loop_mode])
		for i in a.get_track_count():
			var t := a.track_get_type(i)
			var kn := a.track_get_key_count(i)
			var extra := ""
			if kn > 0:
				if t == Animation.TYPE_ROTATION_3D:
					extra = "q0=%s" % a.track_get_key_value(i, 0)
				elif t == Animation.TYPE_POSITION_3D:
					extra = "p0=%s" % a.track_get_key_value(i, 0)
				else:
					extra = "v0=%s" % a.track_get_key_value(i, 0)
			print("  trk[%d] type=%d path=%s keys=%d t0=%.3f %s" % [i, t, a.track_get_path(i), kn, a.track_get_key_time(i, 0) if kn > 0 else -1.0, extra])
	quit(0)
