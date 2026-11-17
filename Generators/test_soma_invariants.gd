extends SceneTree
## Регресс-тест нейро-кастов (v2, 17.11.26 — после фикса конъюгации в ретаргете):
## 1) все 8 клипов на месте в shared_animations.res;
## 2) ПОЗА СКИНА = ПОЗА ИСТОЧНИКА: FK-позиции кистей из треков совпадают с RAW
##    SOMA в кадрах 0/середина/конец (≤0.25 м) — главный гейт качества
##    (v1 проверял «t=0=rest», чем ЗАКРЕПЛЯЛ Т-позу-вспышку на старте каста);
## 3) hips t=0 = rest-локал (по построению: root0−root0=0) — регресс левитации;
## 4) бёдра в середине клипа не левитируют (|y − rest_y| ≤ 0.15).
## Запуск: --headless -s res://Generators/test_soma_invariants.gd

const NAMES := ["Cast_Enter", "Cast_Loop", "Cast_Shoot", "Cast_Shoot_L",
	"Cast_Exit", "Throw", "Pistol_Shoot", "Pistol_Shoot_L"]
const RAW_DIR := {  # имя в библиотеке → каталог neuro_soma
	"Cast_Enter": "cast_enter", "Cast_Loop": "cast_loop", "Cast_Shoot": "cast_shoot",
	"Cast_Shoot_L": "cast_shoot_b", "Cast_Exit": "cast_exit", "Throw": "throw",
	"Pistol_Shoot": "pistol_shoot", "Pistol_Shoot_L": "pistol_shoot_l",
}
const LIB_PATH := "res://Graphics/Animations/shared_animations.res"
const SOMA_BASE := "res://Graphics/Animations/neuro_soma"
const TOL_HAND := 0.25   # м, расхождение кисти SKIN vs RAW
const TOL_HIPS := 0.15   # м, левитация бёдер

const SOMA_NAMES := ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw",
	"LeftEye", "RightEye", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"LeftHandThumbEnd", "LeftHandMiddleEnd", "RightShoulder", "RightArm", "RightForeArm",
	"RightHand", "RightHandThumbEnd", "RightHandMiddleEnd", "LeftLeg", "LeftShin",
	"LeftFoot", "LeftToeBase", "RightLeg", "RightShin", "RightFoot", "RightToeBase"]
const SOMA_PARENTS := [-1, 0, 1, 2, 3, 4, 5, 6, 6, 6, 3, 10, 11, 12, 13, 13, 3, 16, 17, 18, 19, 19, 0, 22, 23, 24, 0, 26, 27, 28]
const SOMA_OFFSETS := [
	Vector3(0, 0, 0), Vector3(-0.00013727, 0.0500376256, -0.00053726669),
	Vector3(-1.86574103e-9, 0.0712530139, -0.000298248546),
	Vector3(-5.75188398e-9, 0.0755006305, -0.00815970992),
	Vector3(-0.00181676517, 0.263112953, -0.00553348292),
	Vector3(-2.85102231e-8, 0.0770939664, 0.0230258546),
	Vector3(-4.5975437e-8, 0.0612891595, 0.0195370861),
	Vector3(2.63687901e-5, 0.0047559225, 0.0309494062),
	Vector3(0.0320638079, 0.0538020513, 0.0758688308),
	Vector3(-0.0322244017, 0.05361869, 0.0755823359),
	Vector3(0.0162165175, 0.232371641, 0.0511341324),
	Vector3(0.149198457, 2.19397873e-8, -0.0550232576),
	Vector3(0.287393078, 2.50268389e-9, -2.58787737e-5),
	Vector3(0.270939812, -7.06625108e-9, 2.60897248e-5),
	Vector3(0.122686267, -0.0322017573, 0.0483306876),
	Vector3(0.190119595, -0.00312878387, -0.000339570373),
	Vector3(-0.0138011824, 0.231803086, 0.0521415786),
	Vector3(-0.150371962, 1.17387901e-7, -0.0554560437),
	Vector3(-0.287366393, 1.87628082e-8, -2.59709359e-5),
	Vector3(-0.271336198, -1.16767401e-9, 2.61269368e-5),
	Vector3(-0.122642483, -0.0321145448, 0.0480403904),
	Vector3(-0.190005945, -0.00306615542, -0.0003157343),
	Vector3(0.10043214, -0.0843452671, 0.0259565473),
	Vector3(-1e-8, -0.432217537, -0.00802912805),
	Vector3(1e-8, -0.421550959, -0.0348152298),
	Vector3(0, -0.0505947206, 0.132315294),
	Vector3(-0.10047278, -0.0829525995, 0.0262031695),
	Vector3(1e-8, -0.433622059, -0.00805555828),
	Vector3(2e-8, -0.421173943, -0.0347839785),
	Vector3(-3.42907669e-9, -0.0507960932, 0.132841956),
]

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
	var parent_name: Dictionary = {}
	for i in skel.get_bone_count():
		var bn: String = skel.get_bone_name(i).replace("mixamorig1_", "mixamorig_")
		rest_local[bn] = skel.get_bone_rest(i)
		var pi: int = skel.get_bone_parent(i)
		parent_name[bn] = skel.get_bone_name(pi).replace("mixamorig1_", "mixamorig_") if pi >= 0 else ""
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
		var rf := FileAccess.open("%s/%s/root_positions.f32" % [SOMA_BASE, RAW_DIR[n]], FileAccess.READ)
		var ff := FileAccess.open("%s/%s/local_rotations_xyzw.f32" % [SOMA_BASE, RAW_DIR[n]], FileAccess.READ)
		if rf == null or ff == null:
			print("SOMA-INV FAIL %s: нет raw .f32" % n)
			fails += 1
			continue
		var roots: PackedFloat32Array = rf.get_buffer(rf.get_length()).to_float32_array()
		var rots: PackedFloat32Array = ff.get_buffer(ff.get_length()).to_float32_array()
		rf.close()
		ff.close()
		var frames := rots.size() / (SOMA_NAMES.size() * 4)

		# Гейт 1: поза скина = поза источника (кисти, 3 контрольных кадра).
		var worst_d := 0.0
		var worst_at := ""
		for frac in [0.0, 0.5, 0.99]:
			var k := mini(int(frames * frac), frames - 1)
			# Хвост Cast_Loop — кроссфейд шва на позу кадра 0 (фикс 43°): там
			# эталон = кадр 0, а не unfaded raw (иначе ложный провал).
			var ref_frame := 0 if (n == "Cast_Loop" and frac > 0.9) else k
			var g: Dictionary = {}
			_soma_fk(roots, rots, ref_frame, g)
			var t: float = minf(k / 30.0, a.length - 0.001)
			var gs: Dictionary = {}
			_skin_fk(a, rest_local, parent_name, t, gs)
			for side in ["LeftHand", "RightHand"]:
				var target: String = "mixamorig_" + side
				if not gs.has(target):
					continue
				var d: float = g[side].origin.distance_to(gs[target].origin)
				if d > worst_d:
					worst_d = d
					worst_at = "t%.2f %s" % [t, side]
		# Гейт 2: hips t=0 = rest-локал; Гейт 3: нет левитации в середине.
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
		if worst_d > TOL_HAND or not hips_ok:
			fails += 1
			print("SOMA-INV FAIL %s: кисти SKIN≠RAW (макс %.2f м в %s)" % [n, worst_d, worst_at])
		else:
			print("SOMA-INV OK %s: кисти SKIN≈RAW (макс %.2f м), бёдра mid y=%.2f (rest %.2f)" % [n, worst_d, hips_y_mid, rest_hips_y])

	if fails > 0:
		print("SOMA-INV: %d провалов" % fails)
		quit(1)
		return
	print("SOMA-INV: ALL PASS")
	quit(0)

## FK сырого SOMA-кадра.
func _soma_fk(roots: PackedFloat32Array, rots: PackedFloat32Array, frame: int, g: Dictionary) -> void:
	var nj := SOMA_NAMES.size()
	for j in nj:
		var base := frame * nj * 4 + j * 4
		var q := Quaternion(rots[base], rots[base + 1], rots[base + 2], rots[base + 3])
		var pi: int = SOMA_PARENTS[j]
		if pi < 0:
			g[SOMA_NAMES[j]] = Transform3D(Basis(q), Vector3(roots[frame * 3], roots[frame * 3 + 1], roots[frame * 3 + 2]))
		else:
			g[SOMA_NAMES[j]] = g[SOMA_NAMES[pi]] * Transform3D(Basis(q), SOMA_OFFSETS[j])

## FK скина в момент t: локальные кватернионы из треков анимации (фолбэк rest).
func _skin_fk(anim: Animation, rest_local: Dictionary, parent_name: Dictionary, t: float, g: Dictionary) -> void:
	var locals: Dictionary = {}
	for bn in rest_local:
		locals[bn] = rest_local[bn]
	for t_i in anim.get_track_count():
		if anim.track_get_type(t_i) != Animation.TYPE_ROTATION_3D:
			continue
		var bn := str(anim.track_get_path(t_i)).get_slice(":", 1)
		if locals.has(bn):
			var q: Quaternion = anim.rotation_track_interpolate(t_i, t)
			locals[bn].basis = Basis(q)
	for bn in locals:  # порядок словаря = порядок костей скелета (родитель раньше)
		var pn: String = parent_name[bn]
		g[bn] = g[pn] * locals[bn] if pn != "" and g.has(pn) else locals[bn]

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null
