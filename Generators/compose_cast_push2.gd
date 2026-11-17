extends SceneTree
## РЕМАП-КОМПОЗИТ cast_push v3 (раунд 7, итерация 2 по вердикту юзера
## «внизу у промежности что-то крутит, вперёд не вытягивает»).
##
## Причины провала v2 (числа зонда):
## 1) питч руки 15° (компенсация высоты) утопил толчок: пик y1.09-1.22 z0.59 —
##    на рослом доноре (hips 0.99) это НИЗ ЖИВОТА. Юзер прав.
## 2) дрейф тела/левой донора (кисть x-0.11→+0.30 на высоте пояса) читался
##    как «что-то крутит у промежности».
## 3) z0.59 против одобренных юзером z0.82 (панч) = «не вытягивает вперёд».
##
## v3: тело/левая = ЗАМОРОЗКА кадра 0 донора (никакой суеты); правая цепь —
## глобальная прививка панча (первый сустав к финальному торсу, остальные —
## к панч-родителю); питч руки всего 8°; СПИН1 наклоняется вперёд LEAN_DEG
## в такт толчку (корпус вкладывается в каст — даёт длину выброса и вес);
## таймлайн: k0-4 подъём (idle → панч k10, рука идёт вверх-вперёд одним
## движением), k5-11 толчок (панч k10..k16, пик z~0.77 на k7), k12-16 возврат
## (w=1−smoothstep), k17-23 hold idle. Ожидание: y@пик ~1.34, z_max ~0.77.
## Запуск: --headless -s res://Generators/compose_cast_push2.gd

const NJ := 30
const SRC_PUNCH := "D:/nn/kimodo.cpp/out/cast_push_a"      # правая цепь (толчок)
const SRC_DONOR := "D:/nn/kimodo.cpp/out/bent_left_donor"  # поза тела/левой (кадр 0)
const DST := "res://Graphics/Animations/neuro_soma/cast_push"
const CHAIN_R := [16, 17, 18, 19]  # RightShoulder/Arm/ForeArm/Hand
const RISE_END := 4                # кадры 0..4: подъём idle → панч k10
const THRUST_SRC := 10             # кадры 5..11 = панч k10..k16
const THRUST_END := 11             # последний кадр толчка (панч k16)
const FALL_FRAMES := 4.0           # возврат за 4 кадра (панч k16 → idle)
const LEAN_DEG := 20.0             # наклон корпуса в толчок (Spine1, в такт w)
const PITCH_DOWN_DEG := 0.0        # питч УБРАН (раунд 8): рендер кадров показал
                                   # толчок на поясе; рука с плеча горизонтально

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
	var pr := FileAccess.open(SRC_PUNCH + "/root_positions.f32", FileAccess.READ)
	var pf := FileAccess.open(SRC_PUNCH + "/local_rotations_xyzw.f32", FileAccess.READ)
	var dr := FileAccess.open(SRC_DONOR + "/root_positions.f32", FileAccess.READ)
	var df := FileAccess.open(SRC_DONOR + "/local_rotations_xyzw.f32", FileAccess.READ)
	if pr == null or pf == null or dr == null or df == null:
		print("COMPOSE2 FAIL: нет исходников (нужны out/cast_push_a и out/bent_left_donor)")
		quit(1)
		return
	var proots := pr.get_buffer(pr.get_length()).to_float32_array()
	var prots := pf.get_buffer(pf.get_length()).to_float32_array()
	var droots := dr.get_buffer(dr.get_length()).to_float32_array()
	var drots := df.get_buffer(df.get_length()).to_float32_array()
	pr.close(); pf.close(); dr.close(); df.close()
	var frames := prots.size() / (NJ * 4)
	if drots.size() / (NJ * 4) != frames or frames != 24:
		print("COMPOSE2 FAIL: оба источника должны быть 24 кадра (есть %d)" % frames)
		quit(1)
		return

	# Донорская FK кадра 0 (якоря для наклона торса и прививки руки).
	var g0 := {}
	_fk_one(droots, drots, 0, g0)
	var b_hips: Basis = (g0["Hips"] as Transform3D).basis
	var b_spine1: Basis = (g0["Spine1"] as Transform3D).basis
	var b_chest: Basis = (g0["Chest"] as Transform3D).basis

	var n_roots := PackedFloat32Array()
	n_roots.resize(frames * 3)              # тело заморожено: корни кадра 0 на КАЖДЫЙ кадр
	for k in frames:
		n_roots[k * 3] = droots[0]
		n_roots[k * 3 + 1] = droots[1]
		n_roots[k * 3 + 2] = droots[2]
	# Все суставы = локали кадра 0 донора (заморозка; правую цепь и Spine1 перепишем).
	var n_rots := PackedFloat32Array()
	n_rots.resize(frames * NJ * 4)
	for k in frames:
		for i in NJ * 4:
			n_rots[k * NJ * 4 + i] = drots[i]

	var q_pitch := Quaternion(Vector3(1, 0, 0), deg_to_rad(PITCH_DOWN_DEG))
	for k in frames:
		# Таймлайн правой руки (и наклона корпуса).
		var src_k := THRUST_SRC
		var w := 1.0
		if k <= RISE_END:
			src_k = THRUST_SRC
			w = smoothstep(0.0, 1.0, float(k) / float(RISE_END))
		elif k <= THRUST_END:
			src_k = THRUST_SRC + (k - RISE_END - 1)   # k5→панч k10 ... k11→панч k16
		else:
			src_k = THRUST_END_SRC()
			w = 1.0 - smoothstep(0.0, 1.0, (float(k) - float(THRUST_END)) / FALL_FRAMES)
		# Наклон корпуса: Spine1 в мире на LEAN_DEG*w (вся верхняя часть выше —
		# жёстко с ним: локали Spine2/Chest остаются донорскими).
		var lean_q := Quaternion(Vector3(1, 0, 0), deg_to_rad(LEAN_DEG * w))
		var d1 := k * NJ * 4 + 1 * 4
		var q_spine1 := (b_hips.get_rotation_quaternion().inverse() * lean_q * b_spine1.get_rotation_quaternion()).normalized()
		n_rots[d1] = q_spine1.x
		n_rots[d1 + 1] = q_spine1.y
		n_rots[d1 + 2] = q_spine1.z
		n_rots[d1 + 3] = q_spine1.w
		# Финальный (наклонённый) глобал груди: жёстко = lean × донорский.
		var chest_pos: Vector3 = (g0["Hips"] as Transform3D).origin + lean_q * ((g0["Chest"] as Transform3D).origin - (g0["Hips"] as Transform3D).origin)
		var b_chest_final: Basis = Basis(lean_q) * b_chest
		# FK панча на кадре src_k.
		var gp := {}
		_fk_one(proots, prots, src_k, gp)
		for j: int in CHAIN_R:
			var pi: int = SOMA_PARENTS[j]
			var b_parent_final: Basis
			if j == CHAIN_R[0]:
				b_parent_final = b_chest_final   # первый сустав — к наклонённому торсу
			else:
				b_parent_final = (gp[SOMA_JOINT_NAME(pi)] as Transform3D).basis
			var b_punch: Basis = (gp[SOMA_JOINT_NAME(j)] as Transform3D).basis
			var q_target := (b_parent_final.inverse() * b_punch).get_rotation_quaternion().normalized()
			# Питч руки вниз в мире (конъюгация по финальному родителю).
			var q_parent := b_parent_final.get_rotation_quaternion().normalized()
			q_target = (q_parent.inverse() * q_pitch * q_parent * q_target).normalized()
			var dst := k * NJ * 4 + j * 4
			var q_donor := Quaternion(drots[dst], drots[dst + 1], drots[dst + 2], drots[dst + 3])
			var qs := q_donor.slerp(q_target, w)   # подъём/возврат: вес идёт ОТ панча К idle
			n_rots[dst] = qs.x
			n_rots[dst + 1] = qs.y
			n_rots[dst + 2] = qs.z
			n_rots[dst + 3] = qs.w
	DirAccess.make_dir_recursive_absolute(DST)
	var fr := FileAccess.open(DST + "/root_positions.f32", FileAccess.WRITE)
	fr.store_buffer(n_roots.to_byte_array())
	fr.close()
	var fv := FileAccess.open(DST + "/local_rotations_xyzw.f32", FileAccess.WRITE)
	fv.store_buffer(n_rots.to_byte_array())
	fv.close()
	var pf2 := FileAccess.open(DST + "/prompt.txt", FileAccess.WRITE)
	pf2.store_string("Ремап-композит v3 (compose_cast_push2.gd, раунд 7, итер.2): тело+левая заморожены (кадр 0 bent_left_donor seed31); правая цепь — глобальная прививка панча cast_push_a (k10..k16, пик ~k7), питч 8°, Spine1 наклоняется вперёд 20° в такт толчку. Причины v2-провала: питч 15° утопил толчок до низа живота (вердикт юзера «у промежности крутит»), дрейф донора читался суетой, z0.59 < одобренных z0.82.\n")
	pf2.close()
	print("COMPOSE2 OK: %d кадров → %s" % [frames, DST])
	quit(0)

func THRUST_END_SRC() -> int:
	return THRUST_SRC + (THRUST_END - RISE_END - 1)   # панч-кадр на конце толчка (k16)

func SOMA_JOINT_NAME(j: int) -> String:
	var names := ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw",
		"LeftEye", "RightEye", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"LeftHandThumbEnd", "LeftHandMiddleEnd", "RightShoulder", "RightArm", "RightForeArm",
		"RightHand", "RightHandThumbEnd", "RightHandMiddleEnd", "LeftLeg", "LeftShin",
		"LeftFoot", "LeftToeBase", "RightLeg", "RightShin", "RightFoot", "RightToeBase"]
	return names[j]

## FK одного SOMA-кадра (глобальные трансформы всех костей).
func _fk_one(roots: PackedFloat32Array, rots: PackedFloat32Array, frame: int, g: Dictionary) -> void:
	for j in NJ:
		var base := frame * NJ * 4 + j * 4
		var q := Quaternion(rots[base], rots[base + 1], rots[base + 2], rots[base + 3])
		var pi: int = SOMA_PARENTS[j]
		if pi < 0:
			g[SOMA_JOINT_NAME(j)] = Transform3D(Basis(q), Vector3(roots[frame * 3], roots[frame * 3 + 1], roots[frame * 3 + 2]))
		else:
			g[SOMA_JOINT_NAME(j)] = (g[SOMA_JOINT_NAME(pi)] as Transform3D) * Transform3D(Basis(q), SOMA_OFFSETS[j])
