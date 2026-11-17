extends SceneTree
## Численный гейт «хореографии рук» нейро-клипов (17.11.26, вердикт юзера
## «двумя руками держится в центре» + «фаербол криво»): FK по всем кадрам RAW
## SOMA из произвольного каталога (neuro_soma или out/), метрики кистей/бёдер,
## вердикт PASS/FAIL по типу клипа. Гейт прогоняется ДО ретаргета — мусорные
## генерации не доезжают до игры.
##   pistol_shoot   — правая вытянута вперёд (R_z_max≥0.45, y∈[1.10,1.65] в пике),
##                    левая вся клипа низко (y<1.10, z<0.35);
##   pistol_shoot_l — зеркально (левая вперёд, правая низко);
##   throw          — замах: ∃кадр R_y≥1.55 при R_z≤0.15; выброс: ∃кадр
##                    R_z≥0.35 при y∈[1.05,1.70]; левая y<1.55 всё клипа.
## Бёдра у всех типов: |y−0.93|≤0.20 и снос xz<0.35 (ноги стоят).
## Запуск: --headless -s res://Generators/probe_hand_path.gd -- <type> <dir> [<type> <dir> ...]

const NJ := 30
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
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() % 2 != 0:
		print("GATE FAIL: аргументы: <type> <dir> парами")
		quit(1)
		return
	var fails := 0
	var i := 0
	while i < args.size():
		var type: String = args[i]
		var dir: String = args[i + 1]
		i += 2
		if not _probe(type, dir):
			fails += 1
	if fails > 0:
		print("GATE: %d провалов" % fails)
		quit(1)
	else:
		print("GATE: ALL PASS")
		quit(0)

func _probe(type: String, dir: String) -> bool:
	var rf := FileAccess.open(dir + "/root_positions.f32", FileAccess.READ)
	var ff := FileAccess.open(dir + "/local_rotations_xyzw.f32", FileAccess.READ)
	if rf == null or ff == null:
		print("GATE %s [%s]: FAIL — нет .f32" % [type, dir])
		return false
	var roots: PackedFloat32Array = rf.get_buffer(rf.get_length()).to_float32_array()
	var rots: PackedFloat32Array = ff.get_buffer(ff.get_length()).to_float32_array()
	rf.close()
	ff.close()
	var frames := rots.size() / (NJ * 4)
	if frames < 2:
		print("GATE %s [%s]: FAIL — %d кадров" % [type, dir, frames])
		return false
	var label: String = dir.get_file()
	if label == "":
		label = dir
	# Метрики по всем кадрам.
	var r_z_max := -99.0
	var r_z_max_k := -1
	var l_z_max := -99.0
	var r_y_max := -99.0
	var l_y_max := -99.0
	var l_y_min := 99.0
	var r_y_min := 99.0
	var r_y_at_zmax := 0.0
	var l_y_at_zmax := 0.0
	var r_z_at_ymax := -99.0
	var r_y0 := 0.0    # старт правой (гейт гард-старта)
	var r_yN := 0.0    # финиш правой
	var l_y0 := 0.0
	var l_yN := 0.0
	var l_z_min := 99.0  # минимум выноса левой (гейт «за спину»)
	var r_dwell := 0     # кадров у лица без выноса (гард-пауза)
	var l_dwell := 0
	var hips_bad := ""
	var windup_k := -1
	var release_k := -1
	for k in frames:
		var g: Dictionary = {}
		_soma_fk(roots, rots, k, g)
		var rh: Vector3 = (g["RightHand"] as Transform3D).origin
		var lh: Vector3 = (g["LeftHand"] as Transform3D).origin
		var hp: Vector3 = (g["Hips"] as Transform3D).origin
		if absf(hp.y - 0.93) > 0.20:
			hips_bad = "y=%.2f@k%d" % [hp.y, k]
		if k > 0 and Vector2(hp.x, hp.z).distance_to(Vector2(roots[0], roots[2])) > 0.35:
			hips_bad = "снос xz=%.2f@k%d" % [Vector2(hp.x, hp.z).distance_to(Vector2(roots[0], roots[2])), k]
		if rh.z > r_z_max: r_z_max = rh.z; r_z_max_k = k; r_y_at_zmax = rh.y
		if lh.z > l_z_max: l_z_max = lh.z; l_y_at_zmax = lh.y
		if lh.z < l_z_min: l_z_min = lh.z
		if rh.y > r_y_max: r_y_max = rh.y; r_z_at_ymax = rh.z
		l_y_max = maxf(l_y_max, lh.y)
		l_y_min = minf(l_y_min, lh.y)
		r_y_min = minf(r_y_min, rh.y)
		if k == 0:
			r_y0 = rh.y
			l_y0 = lh.y
		if k == frames - 1:
			r_yN = rh.y
			l_yN = lh.y
		# Гард-пауза: кисть у лица (y>1.30) и НЕ вытянута (z<0.45) — то самое
		# «сначала подносит ко лбу, потом каст» (вердикт юзера).
		if rh.y > 1.30 and rh.z < 0.45: r_dwell += 1
		if lh.y > 1.30 and lh.z < 0.45: l_dwell += 1
		if type == "throw":
			if rh.y >= 1.55 and rh.z <= 0.15 and windup_k < 0: windup_k = k
			if rh.z >= 0.35 and rh.y >= 1.05 and rh.y <= 1.70 and release_k < 0: release_k = k
		if k % 4 == 0 or k == frames - 1:
			print("PATH %s k%02d L(x%+.2f y%.2f z%+.2f) R(x%+.2f y%.2f z%+.2f)" % [label, k, lh.x, lh.y, lh.z, rh.x, rh.y, rh.z])
	# Вердикт по типу.
	var why := ""
	var ok := hips_bad == ""
	if not ok: why = "бёдра " + hips_bad
	match type:
		"pistol_shoot":
			if r_z_max < 0.45: ok = false; why = "R_z_max=%.2f<0.45" % r_z_max
			elif r_y_at_zmax < 1.10 or r_y_at_zmax > 1.65: ok = false; why = "R_y@пик=%.2f вне [1.10,1.65]" % r_y_at_zmax
			elif l_y_max >= 1.10: ok = false; why = "левая поднимается y_max=%.2f" % l_y_max
			elif l_z_max >= 0.35: ok = false; why = "левая вперёд z_max=%.2f" % l_z_max
		"pistol_shoot_l":
			if l_z_max < 0.45: ok = false; why = "L_z_max=%.2f<0.45" % l_z_max
			elif l_y_at_zmax < 1.10 or l_y_at_zmax > 1.65: ok = false; why = "L_y@пик=%.2f вне [1.10,1.65]" % l_y_at_zmax
			elif r_y_max >= 1.10: ok = false; why = "правая поднимается y_max=%.2f" % r_y_max
			elif r_z_max >= 0.35: ok = false; why = "правая вперёд z_max=%.2f" % r_z_max
		"cast_push":
			# Единый каст-жест (фаербол/сердечко/луч): толчок вперёд на высоте
			# груди, БЕЗ высокого замаха («машет как волейбол» — вердикт юзера).
			if r_z_max < 0.40: ok = false; why = "R_z_max=%.2f<0.40" % r_z_max
			elif r_y_at_zmax < 1.05 or r_y_at_zmax > 1.45: ok = false; why = "R_y@пик=%.2f вне [1.05,1.45]" % r_y_at_zmax
			elif r_y_max > 1.50: ok = false; why = "замах выше груди y_max=%.2f" % r_y_max
			elif r_dwell >= 3: ok = false; why = "гард-пауза у лица %d кадров" % r_dwell
			elif l_y_max >= 1.10: ok = false; why = "левая поднимается y_max=%.2f" % l_y_max
			elif l_z_max >= 0.35: ok = false; why = "левая вытянута вперёд z_max=%.2f" % l_z_max
		"cast_push_l":
			# Точное зеркало cast_push (данные зеркалятся mirror_cast_push.gd):
			# пороги те же, стороны поменяны. Ловит ошибку самого зеркала.
			if l_z_max < 0.40: ok = false; why = "L_z_max=%.2f<0.40" % l_z_max
			elif l_y_at_zmax < 1.05 or l_y_at_zmax > 1.45: ok = false; why = "L_y@пик=%.2f вне [1.05,1.45]" % l_y_at_zmax
			elif l_y_max > 1.50: ok = false; why = "замах выше груди y_max=%.2f" % l_y_max
			elif l_dwell >= 3: ok = false; why = "гард-пауза у лица %d кадров" % l_dwell
			elif r_y_max >= 1.10: ok = false; why = "правая поднимается y_max=%.2f" % r_y_max
			elif r_z_max >= 0.35: ok = false; why = "правая вытянута вперёд z_max=%.2f" % r_z_max
		"left_bent_front":
			# Донор пассивной руки (вердикт юзера: «висящая уходит за спину —
			# пусть будет согнутая, но спереди»): кисть всё клипа не за спиной,
			# хоть раз ощутимо вперёд, на высоте пояса-ниже груди.
			if l_z_min < -0.05: ok = false; why = "левая уходит за спину z_min=%.2f" % l_z_min
			elif l_z_max < 0.12: ok = false; why = "левая не впереди z_max=%.2f" % l_z_max
			elif l_y_max > 1.20: ok = false; why = "левая выше груди y_max=%.2f" % l_y_max
			elif l_y_min < 0.60: ok = false; why = "левая слишком низко y_min=%.2f" % l_y_min
		"throw":
			if windup_k < 0: ok = false; why = "нет замаха (R_y≥1.55 при z≤0.15; R_y_max=%.2f)" % r_y_max
			elif release_k < 0: ok = false; why = "нет выброса (R_z≥0.35)"
			elif l_y_max >= 1.55: ok = false; why = "левая выше плеч y_max=%.2f" % l_y_max
		_:
			ok = false
			why = "неизвестный тип " + type
	if ok:
		print("GATE %s [%s]: PASS (%s)" % [type, label, _summ(type, r_z_max, r_z_max_k, l_z_max, r_y_max, l_y_max, l_y_min, r_y_min, l_z_min)])
	else:
		print("GATE %s [%s]: FAIL — %s" % [type, label, why])
	return ok

func _summ(type: String, r_z_max: float, r_z_max_k: int, l_z_max: float, r_y_max: float, l_y_max: float, l_y_min: float, r_y_min: float, l_z_min: float) -> String:
	match type:
		"pistol_shoot":
			return "R_z_max=%.2f@k%d L_y∈[%.2f,%.2f]" % [r_z_max, r_z_max_k, l_y_min, l_y_max]
		"pistol_shoot_l":
			return "L_z_max=%.2f R_y∈[%.2f,%.2f]" % [l_z_max, r_y_min, r_y_max]
		"cast_push":
			return "R_z_max=%.2f@k%d R_y_max=%.2f L_y_max=%.2f" % [r_z_max, r_z_max_k, r_y_max, l_y_max]
		"cast_push_l":
			return "L_z_max=%.2f L_y_max=%.2f R_y_max=%.2f" % [l_z_max, l_y_max, r_y_max]
		"left_bent_front":
			return "L_z∈[%.2f,%.2f] L_y∈[%.2f,%.2f]" % [l_z_min, l_z_max, l_y_min, l_y_max]
		"throw":
			return "R_y_max=%.2f L_y_max=%.2f" % [r_y_max, l_y_max]
	return ""

## FK сырого SOMA-кадра (глобальные трансформы всех костей).
func _soma_fk(roots: PackedFloat32Array, rots: PackedFloat32Array, frame: int, g: Dictionary) -> void:
	for j in NJ:
		var base := frame * NJ * 4 + j * 4
		var q := Quaternion(rots[base], rots[base + 1], rots[base + 2], rots[base + 3])
		var pi: int = SOMA_PARENTS[j]
		if pi < 0:
			g[SOMA_NAMES[j]] = Transform3D(Basis(q), Vector3(roots[frame * 3], roots[frame * 3 + 1], roots[frame * 3 + 2]))
		else:
			g[SOMA_NAMES[j]] = (g[SOMA_NAMES[pi]] as Transform3D) * Transform3D(Basis(q), SOMA_OFFSETS[j])
