extends SceneTree
## Зонд: лейеринг кастов поверх локомоции. Механика Godot 4.8: ВТОРОЙ
## AnimationPlayer (в дереве ПОСЛЕ основного, тот же root_node) с UB-вариантом
## клипа (ротации ног + позиция Hips сняты) пишет поверх продолжающегося Run.
## Ноги ведёт локомоция, верх — каст.
##
## Вопросы: A) ноги живы? B) каст виден? C) вход бленда плавный?
##          D) capture-методы? E) capture лечит вход?
## Запуск: --headless -s res://Generators/probe_upper_layer.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"

const LEG_BONES := [
	"mixamorig_LeftUpLeg", "mixamorig_RightUpLeg",
	"mixamorig_LeftLeg", "mixamorig_RightLeg",
	"mixamorig_LeftFoot", "mixamorig_RightFoot",
	"mixamorig_LeftToeBase", "mixamorig_RightToeBase",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame

	var loco: AnimationPlayer = player.get_node("GraphicsWrapper/AnimationPlayer")
	var skel: Skeleton3D = _find_skeleton(player)
	if loco == null or skel == null:
		print("PROBE FAIL: нет плеера или скелета")
		quit(1)
		return

	var castp := AnimationPlayer.new()
	loco.get_parent().add_child(castp)
	castp.root_node = loco.root_node
	var src_lib = load(LIB_PATH)
	var clib := AnimationLibrary.new()
	clib.add_animation("Heart_Cast_UB", _make_ub(src_lib.get_animation("Heart_Cast")))
	castp.add_animation_library("", clib)

	var caps := []
	for m in castp.get_method_list():
		if String(m["name"]).contains("capture"):
			caps.append(String(m["name"]))
	print("PROBE D: capture-методы: ", ", ".join(caps))

	# SEQ A: чистый Run — база осцилляции стопы
	loco.play("Run")
	for i in 40:
		await process_frame
	var base_z: Array[float] = []
	for i in 20:
		await process_frame
		base_z.append(_bone_pos(skel, "mixamorig_LeftFoot").z)
	var base_spread := _spread(base_z)
	print("PROBE A: база Run — spread стопы Z=%.3f м" % base_spread)

	# SEQ B: UB-каст поверх продолжающегося Run (бленд 0.1, без capture)
	castp.play("Heart_Cast_UB", 0.1)
	var hand_y: Array[float] = []
	var foot_z: Array[float] = []
	var deltas: Array[float] = []
	var prev := _bone_pos(skel, "mixamorig_LeftHand")
	for i in 70:
		await process_frame
		var h := _bone_pos(skel, "mixamorig_LeftHand")
		hand_y.append(h.y)
		foot_z.append(_bone_pos(skel, "mixamorig_LeftFoot").z)
		deltas.append(h.distance_to(prev))
		prev = h
	var cast_spread := _spread(foot_z)
	print("PROBE B: ноги при касте — spread Z=%.3f (база %.3f) → %s" % [
		cast_spread, base_spread,
		"ЖИВЫ" if cast_spread > base_spread * 0.4 else "ЗАМЕРЛИ/REST"])
	print("PROBE B2: кисть Y старт=%.3f конец=%.3f spread=%.3f → %s" % [
		hand_y[0], hand_y[-1], _spread(hand_y),
		"КАСТ ВИДЕН" if _spread(hand_y) > 0.2 else "КАСТ НЕ ВИДЕН"])

	# SEQ C: вход бленда — макс сдвиг кисти за один кадр в первые 10 кадров
	var snap := 0.0
	for d in deltas.slice(0, 10):
		snap = maxf(snap, d)
	print("PROBE C: вход бленда — макс сдвиг кисти за кадр=%.3f м → %s" % [
		snap, "ГЛАДКО" if snap < 0.2 else "РЫВОК (рест-проход, нужен capture)"])

	# SEQ E: тот же каст с capture (вход из текущей позы бега)
	castp.stop()
	loco.stop()
	loco.play("Run")
	for i in 40:
		await process_frame
	castp.play("Heart_Cast_UB", 0.1)
	castp.capture("Heart_Cast_UB", 0.1)
	print("PROBE E: capture вызван (void)")
	var deltas2: Array[float] = []
	var prev2 := _bone_pos(skel, "mixamorig_LeftHand")
	for i in 20:
		await process_frame
		var h := _bone_pos(skel, "mixamorig_LeftHand")
		deltas2.append(h.distance_to(prev2))
		prev2 = h
	var snap2 := 0.0
	for d in deltas2.slice(0, 10):
		snap2 = maxf(snap2, d)
	print("PROBE E: вход с capture — макс сдвиг за кадр=%.3f м → %s" % [
		snap2, "ГЛАДКО" if snap2 < 0.2 else "ВСЁ ЕЩЁ РЫВОК"])
	quit(0)

## UB-вариант: снимаем ротации ног и позицию Hips, остальное как есть.
func _make_ub(src: Animation) -> Animation:
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	var removed := []
	for i in src.get_track_count():
		var t := src.track_get_type(i)
		var path := String(src.track_get_path(i))
		var bone := path.substr(path.rfind(":") + 1)
		var drop := false
		if bone in LEG_BONES:
			drop = true
		elif bone == "mixamorig_Hips" and t == Animation.TYPE_POSITION_3D:
			drop = true
		if drop:
			removed.append(bone)
			continue
		var ni := out.add_track(t)
		out.track_set_path(ni, src.track_get_path(i))
		out.track_set_interpolation_type(ni, src.track_get_interpolation_type(i))
		for k in src.track_get_key_count(i):
			out.track_insert_key(ni, src.track_get_key_time(i, k), src.track_get_key_value(i, k))
	print("PROBE UB: треков %d → %d (снято: %s)" % [
		src.get_track_count(), out.get_track_count(), ", ".join(removed)])
	return out

func _bone_pos(skel: Skeleton3D, bone: String) -> Vector3:
	var bi := skel.find_bone(bone)
	return (skel.global_transform * skel.get_bone_global_pose(bi)).origin

func _spread(arr: Array) -> float:
	var mn := 1e9
	var mx := -1e9
	for v in arr:
		mn = minf(mn, v)
		mx = maxf(mx, v)
	return mx - mn

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
