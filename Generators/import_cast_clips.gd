extends SceneTree
## ПЕРЕНОС КАСТ-КЛИПОВ ИЗ ДРУГИХ БИБЛИОТЕК (27.11.26).
##
## Зачем: каст-слой (CastAnimationLayer) видит ТОЛЬКО ual_casts_test.res.
## Часть годных жестов лежит в других библиотеках и кастам недоступна.
##
## ПОЧЕМУ ТАК (история бага сердечка, 27.11.26):
##   Сердечко кастовалось через Spell_Cast. Замер ЧЕРЕЗ РЕАЛЬНЫЙ ПУТЬ
##   (Generators/render_heart_real.gd, а не по сырой библиотеке!) показал:
##   на t=0.85 кисти уходят вбок на 44–61° — то есть в момент спавна снаряда
##   рука в стороне. Плюс alternate_hands рождал сердце то из правой кисти
##   (x≈+0.3), то из левой (x≈−0.3) — юзер видел «сердечко то вправо, то влево,
##   не прямо». Чередование рук = чередование сторон вылета.
##
## ВЫБОР КЛИПА — по замеру, не на глаз:
##   Pistol_Shoot (данные UAL, 0.63 с): ОБЕ кисти вперёд и по центру
##   (R x=+0.00 fwd=+0.41 0°, L x=+0.05 fwd=+0.37 8°) — на всём клипе.
##   Это двуручный толчок вперёд — ровно жест «выброса» для сердечка.
##   Имя «Pistol_Shoot» — легаси (юзер: «какие нахуй пистолеты»,
##   docs/animation_generation.md §16.17), поэтому в каст-библиотеку клип
##   кладётся под СМЫСЛОВЫМ именем Cast_2H_Push (двуручный толчок).
##   Данные не меняются — только имя в библиотеке.
##
## UB-варианты строит build_cast_ub.gd СЛЕДУЮЩИМ шагом (он проходит по всем
## клипам библиотеки). Порядок цепочки:
##   retarget_ual_anims → import_manifest_casts → build_heart_cast
##   → import_cast_clips (ЭТОТ) → build_cast_ub
##
## Идемпотентно: повторный запуск перезаписывает клипы из источника.
## Запуск: --headless -s res://Generators/import_cast_clips.gd

## dst_name → [src_lib, src_name]
const MAP := {
	"Cast_2H_Push": ["res://Graphics/Animations/ual_casts_test.res", "Pistol_Shoot"],
}

const DST_LIB := "res://Graphics/Animations/ual_casts_test.res"

func _init() -> void:
	var dst = load(DST_LIB)
	if dst == null or not (dst is AnimationLibrary):
		print("CAST_CLIPS FAIL: нет библиотеки ", DST_LIB)
		quit(1)
		return
	var done := 0
	for dst_name in MAP:
		var spec: Array = MAP[dst_name]
		var src = load(spec[0])
		if src == null or not (src is AnimationLibrary):
			print("CAST_CLIPS FAIL: нет библиотеки ", spec[0])
			quit(1)
			return
		if not src.has_animation(spec[1]):
			print("CAST_CLIPS FAIL: в %s нет клипа %s" % [spec[0], spec[1]])
			quit(1)
			return
		var a: Animation = src.get_animation(spec[1]).duplicate(true)
		a.resource_name = dst_name
		if dst.has_animation(dst_name):
			dst.remove_animation(dst_name)
		dst.add_animation(dst_name, a)
		done += 1
		print("  + %-14s ← %s (len=%.2f tracks=%d)" % [
			dst_name, spec[1], a.length, a.get_track_count()])
	var err := ResourceSaver.save(dst, DST_LIB)
	print("CAST_CLIPS SAVE err=%d перенесено=%d всего клипов=%d" % [
		err, done, dst.get_animation_list().size()])
	quit(0 if err == OK else 1)
