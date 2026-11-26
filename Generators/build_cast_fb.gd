extends SceneTree
## Фикс разворота тела при касте (баг 26.11.26, видео юзера).
##
## Причина: `PlayerAnimationComponent.play_cast_anim()` СТОЯ играет FULL-BODY
## каст-клип (`CastAnimationLayer.play_full_body`), т.е. вместе с Hips и ногами.
## Full-body клипы UAL/Mixamo несут АБСОЛЮТНЫЙ yaw таза из ретаргета, и он разный:
## Cast_Enter/Loop/Shoot/Exit −41°, Throw/Heart_Cast/Pistol_Shoot/Beam_Push −13°,
## Blade_Swing_B +117°. Hips — корень, поэтому тело прыгает по yaw на 8…158°.
##
## Фикс (данные): во всех НЕ-UB клипах библиотеки **обнуляем yaw таза**, сохраняя
## pitch/roll (наклоны/присед) и позицию. Направлением тела в игре управляет код
## (`face_aim_target` / ввод), клип не должен им распоряжаться.
## Идемпотентно. Порядок в цепочке: retarget_* → build_heart_cast → ЭТОТ СКРИПТ →
## build_cast_ub.gd (UB-Hips не содержит, порядок для UB не важен, но так чище).
## Запуск: --headless -s res://Generators/build_cast_fb.gd

const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"
const HIPS := "mixamorig_Hips"
const YAW_EPS_DEG := 0.01

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load(LIB_PATH)
	if lib == null or not (lib is AnimationLibrary):
		print("FB-YAW FAIL: нет библиотеки ", LIB_PATH)
		quit(1)
		return
	var fixed := 0
	var bad := 0
	for an in lib.get_animation_list():
		var name := String(an)
		if name.ends_with("_UB"):
			continue
		var a: Animation = lib.get_animation(an)
		var tr := _find_rot(a, HIPS)
		if tr < 0:
			continue
		var kc := a.track_get_key_count(tr)
		var yaw_before := 0.0
		var yaw_after_max := 0.0
		for k in kc:
			var q: Quaternion = a.track_get_key_value(tr, k)
			var e := Basis(q).get_euler()   # YXZ по умолчанию: y = yaw
			if k == 0:
				yaw_before = rad_to_deg(e.y)
			e.y = 0.0
			var q_new := Quaternion.from_euler(e)
			a.track_set_key_value(tr, k, q_new)
			yaw_after_max = maxf(yaw_after_max, absf(rad_to_deg(Basis(q_new).get_euler().y)))
		fixed += 1
		var ok := yaw_after_max <= YAW_EPS_DEG
		if not ok:
			bad += 1
		print("  %-20s keys=%3d yaw0=%+.1f° → max|yaw|=%.3f° %s" % [
			name, kc, yaw_before, yaw_after_max, "" if ok else "  <-- НЕ ОБНУЛИЛОСЬ"])
	var err := ResourceSaver.save(lib, LIB_PATH)
	print("FB-YAW SAVE err=%d клипов=%d невалидных=%d" % [err, fixed, bad])
	quit(0 if err == OK and bad == 0 else 1)

func _find_rot(a: Animation, bone: String) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(a.track_get_path(i))
		if p.ends_with(bone) or p.ends_with(":" + bone):
			return i
	return -1