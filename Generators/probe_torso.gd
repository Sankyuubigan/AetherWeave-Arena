extends SceneTree
## Диагностический зонд торса (раунд 7): почему привитая к донору панч-рука
## выше, чем в самом панче (y1.51 vs 1.36). Печатает по кадрам: hips y/yaw,
## Chest/RightShoulder/RightHand глобально — видно, ГДЕ панч теряет высоту
## (корень-присед vs складка позвоночника).
## Запуск: --headless -s res://Generators/probe_torso.gd -- <dir> [кадры через запятую]

const NJ := 30
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
	if args.size() < 1:
		print("TORSO FAIL: нужен <dir>")
		quit(1)
		return
	var dir: String = args[0]
	var rf := FileAccess.open(dir + "/root_positions.f32", FileAccess.READ)
	var ff := FileAccess.open(dir + "/local_rotations_xyzw.f32", FileAccess.READ)
	var roots: PackedFloat32Array = rf.get_buffer(rf.get_length()).to_float32_array()
	var rots: PackedFloat32Array = ff.get_buffer(ff.get_length()).to_float32_array()
	rf.close(); ff.close()
	var frames := rots.size() / (NJ * 4)
	var want: Array = []
	if args.size() > 1:
		for s in String(args[1]).split(","):
			want.append(int(s))
	else:
		for k in frames:
			if k % 4 == 0 or k == frames - 1:
				want.append(k)
	print("TORSO %s frames=%d" % [dir.get_file(), frames])
	for k: int in want:
		if k >= frames:
			continue
		var g := {}
		_fk(roots, rots, k, g)
		var hp := (g["Hips"] as Transform3D).origin
		var ch := (g["Chest"] as Transform3D).origin
		var rs := (g["RightShoulder"] as Transform3D).origin
		var rh := (g["RightHand"] as Transform3D).origin
		var fwd: Vector3 = -(g["Hips"] as Transform3D).basis.z
		var yaw := rad_to_deg(atan2(fwd.x, fwd.z))
		print("T k%02d hips(y%.3f yaw%+.0f) Chest y%.3f RS(x%+.2f y%.3f z%+.2f) RH(x%+.2f y%.3f z%+.2f)" % [k, hp.y, yaw, ch.y, rs.x, rs.y, rs.z, rh.x, rh.y, rh.z])
	quit(0)

func _fk(roots: PackedFloat32Array, rots: PackedFloat32Array, frame: int, g: Dictionary) -> void:
	var names := ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw",
		"LeftEye", "RightEye", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"LeftHandThumbEnd", "LeftHandMiddleEnd", "RightShoulder", "RightArm", "RightForeArm",
		"RightHand", "RightHandThumbEnd", "RightHandMiddleEnd", "LeftLeg", "LeftShin",
		"LeftFoot", "LeftToeBase", "RightLeg", "RightShin", "RightFoot", "RightToeBase"]
	for j in NJ:
		var base := frame * NJ * 4 + j * 4
		var q := Quaternion(rots[base], rots[base + 1], rots[base + 2], rots[base + 3])
		var pi: int = SOMA_PARENTS[j]
		if pi < 0:
			g[names[j]] = Transform3D(Basis(q), Vector3(roots[frame * 3], roots[frame * 3 + 1], roots[frame * 3 + 2]))
		else:
			g[names[j]] = (g[names[pi]] as Transform3D) * Transform3D(Basis(q), SOMA_OFFSETS[j])
