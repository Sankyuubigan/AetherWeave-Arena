extends SceneTree
## Дамп ключей клипов прыжка: длительность + Y-ключи POSITION-треков.
## Цель: найти кадр ОТРЫВА от земли (низ hips Y после приседа), чтобы
## play_jump() стартовал клип с отрыва, а не с приседа («тормоз» в воздухе).

const NAMES := ["Cast_Enter", "Cast_Loop", "Cast_Shoot", "Throw"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load("res://Graphics/Animations/shared_animations.res")
	if lib == null:
		print("DUMP: нет библиотеки")
		quit(1)
		return
	for anim_name in NAMES:
		if not lib.has_animation(anim_name):
			print("DUMP: нет ", anim_name)
			continue
		var anim: Animation = lib.get_animation(anim_name)
		print("=== %s: длина %.3f сек, треков %d ===" % [anim_name, anim.length, anim.get_track_count()])
		for i in mini(anim.get_track_count(), 4):
			print("  трек: ", anim.track_get_path(i), " [", anim.track_get_type(i), "]")
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
				continue
			var path := str(anim.track_get_path(i))
			var kc := anim.track_get_key_count(i)
			print("  POS-трек %s: %d ключей" % [path, kc])
			for k in kc:
				var t := anim.track_get_key_time(i, k)
				var v: Vector3 = anim.track_get_key_value(i, k)
				print("    t=%.3f  Y=%.4f  (X=%.3f Z=%.3f)" % [t, v.y, v.x, v.z])
	quit(0)
