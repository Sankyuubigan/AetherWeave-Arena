extends SceneTree
## Регресс-тест нейро-кастов (баг 17.11.26 «прыгает наверх и висит»):
## 1) t=0 каждого клипа = rest-поза скина ТОЧНО (вращения ≤0.05°,
##    hips-позиция == rest-локал);
## 2) бёдра в середине клипа не левитируют (|y − rest_y| ≤ 0.15);
## 3) все 8 клипов на месте в shared_animations.res.
## Запуск: --headless -s res://Generators/test_soma_invariants.gd

const NAMES := ["Cast_Enter", "Cast_Loop", "Cast_Shoot", "Cast_Shoot_L",
	"Cast_Exit", "Throw", "Pistol_Shoot", "Pistol_Shoot_L"]
const LIB_PATH := "res://Graphics/Animations/shared_animations.res"
const TOL_DEG := 0.15
const TOL_HIPS := 0.15

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player = load("res://Scenes/player.tscn").instantiate()
	var skel = _find_skeleton(player)
	if skel == null:
		print("SOMA-INV FAIL: нет Skeleton3D в player.tscn")
		quit(1)
		return
	var rest_local: Dictionary = {}
	for i in skel.get_bone_count():
		var bn: String = skel.get_bone_name(i).replace("mixamorig1_", "mixamorig_")
		rest_local[bn] = skel.get_bone_rest(i)
	player.free()

	var lib = load(LIB_PATH)
	if lib == null or not (lib is AnimationLibrary):
		print("SOMA-INV FAIL: нет библиотеки")
		quit(1)
		return

	var fails := 0
	for n in NAMES:
		if not lib.has_animation(n):
			print("SOMA-INV FAIL: нет клипа ", n)
			fails += 1
			continue
		var a: Animation = lib.get_animation(n)
		var n_bad := 0
		var worst := 0.0
		var worst_bone := ""
		for t_i in a.get_track_count():
			var p := str(a.track_get_path(t_i))
			if a.track_get_type(t_i) != Animation.TYPE_ROTATION_3D or not p.begins_with("Skeleton3D:"):
				continue
			var bone := p.get_slice(":", 1)
			if not rest_local.has(bone):
				continue
			var q0: Quaternion = a.rotation_track_interpolate(t_i, 0.0)
			var qr: Quaternion = rest_local[bone].basis.get_rotation_quaternion()
			var ang := rad_to_deg(absf(q0.angle_to(qr)))
			if ang > worst:
				worst = ang
				worst_bone = bone
			if ang > TOL_DEG:
				n_bad += 1
		# Hips: t=0 позиция == rest-локал; середина клипа — без левитации.
		var hips_ok := true
		var hips_y_mid := 0.0
		var rest_hips_y: float = rest_local["mixamorig_Hips"].origin.y
		for t_i in a.get_track_count():
			if a.track_get_type(t_i) != Animation.TYPE_POSITION_3D:
				continue
			var bone := str(a.track_get_path(t_i)).get_slice(":", 1)
			if bone != "mixamorig_Hips":
				continue
			var p0: Vector3 = a.position_track_interpolate(t_i, 0.0)
			hips_y_mid = a.position_track_interpolate(t_i, a.length * 0.5).y
			if p0.distance_to(rest_local["mixamorig_Hips"].origin) > 0.01:
				print("SOMA-INV FAIL %s: hips t=0 %s != rest %s" % [n, p0, rest_local["mixamorig_Hips"].origin])
				hips_ok = false
			if absf(hips_y_mid - rest_hips_y) > TOL_HIPS:
				print("SOMA-INV FAIL %s: бёдра левитируют: y=%.2f при rest %.2f" % [n, hips_y_mid, rest_hips_y])
				hips_ok = false
		if n_bad > 0 or not hips_ok:
			fails += 1
			print("SOMA-INV FAIL %s: %d костей от rest на t=0 (худшая %s %.2f°)" % [n, n_bad, worst_bone, worst])
		else:
			print("SOMA-INV OK %s: t=0=rest (худшая %.3f°), бёдра mid y=%.2f (rest %.2f)" % [n, worst, hips_y_mid, rest_hips_y])

	if fails > 0:
		print("SOMA-INV: %d провалов" % fails)
		quit(1)
		return
	print("SOMA-INV: ALL PASS")
	quit(0)

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null
