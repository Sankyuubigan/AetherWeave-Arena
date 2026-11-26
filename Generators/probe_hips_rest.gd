extends SceneTree
## Диагност: rest-ориентация Hips и список клипов каст-библиотеки.
## Запуск: --headless -s res://Generators/probe_hips_rest.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player = load("res://Scenes/player.tscn").instantiate()
	root.add_child(player)
	for i in 5:
		await process_frame
	var skel: Skeleton3D = _find_skel(player)
	if skel == null:
		print("FAIL: нет скелета")
		quit(1)
		return
	var bi := skel.find_bone("mixamorig_Hips")
	var rq: Quaternion = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
	var e := Basis(rq).get_euler()
	print("HIPS REST local: q=", rq, " euler=", e, " deg=", [
		rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)])
	# куда смотрит локальная ось Y кости в пространстве скелета
	var y_axis: Vector3 = skel.get_bone_rest(bi).basis.y
	print("HIPS REST: локальная Y в пространстве скелета = ", y_axis)
	print("HIPS REST: локальная Z в пространстве скелета = ", skel.get_bone_rest(bi).basis.z)
	print("")
	var lib = load("res://Graphics/Animations/ual_casts_test.res")
	var all: Array = lib.get_animation_list()
	var base: Array[String] = []
	var ub := 0
	for n in all:
		if String(n).ends_with("_UB"):
			ub += 1
		else:
			base.append(String(n))
	base.sort()
	print("БИБЛИОТЕКА: всего=%d, _UB=%d, базовых=%d" % [all.size(), ub, base.size()])
	print("БАЗОВЫЕ: ", ", ".join(base))
	print("")
	print("=== локальный euler.y таза по клипам (первый ключ) ===")
	for n in base:
		var a: Animation = lib.get_animation(n)
		var tr := -1
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_ROTATION_3D \
					and String(a.track_get_path(i)).ends_with("mixamorig_Hips"):
				tr = i
				break
		if tr < 0:
			print("  %-22s нет трека Hips" % n)
			continue
		var q: Quaternion = a.track_get_key_value(tr, 0)
		var ee := Basis(q).get_euler()
		print("  %-22s euler=(%+7.2f, %+7.2f, %+7.2f) deg" % [
			n, rad_to_deg(ee.x), rad_to_deg(ee.y), rad_to_deg(ee.z)])
	quit(0)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null
