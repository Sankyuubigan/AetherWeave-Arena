extends SceneTree
## Зонд расхождения «источник vs ретаргет» (17.11.26, вердикт юзера «как кукла»):
## для клипа печатает позиции кистей в кадрах 0/середина/конец:
## 1) RAW SOMA — FK из .f32 (что нейросеть реально сгенерировала);
## 2) SKIN — FK rest-офсетов скина + локальные кватернионы из треков
##    shared_animations.res (что в итоге видит игра).
## Если RAW и SKIN расходятся сильно — врёт ретаргет mid-клипа; если близки —
## кривизна в самих нейро-данных (промпты/диффузия).
## Запуск: --headless -s res://Generators/probe_soma_pose.gd [clip_name]

const BASE := "res://Graphics/Animations/neuro_soma"
const LIB_PATH := "res://Graphics/Animations/shared_animations.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"

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

## clip → имя в библиотеке (raw-каталог == имя клипа).
const CLIPS := ["cast_enter", "cast_loop", "cast_shoot", "cast_exit", "throw", "pistol_shoot", "pistol_shoot_l", "cast_shoot_b"]
const LIB_NAME := {
	"cast_enter": "Cast_Enter", "cast_loop": "Cast_Loop", "cast_shoot": "Cast_Shoot",
	"cast_exit": "Cast_Exit", "throw": "Throw", "pistol_shoot": "Pistol_Shoot",
	"pistol_shoot_l": "Pistol_Shoot_L", "cast_shoot_b": "Cast_Shoot_L",
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player = load(PLAYER_SCENE).instantiate()
	var skel = _find_skeleton(player)
	if skel == null:
		print("POSE FAIL: нет скелета")
		quit(1)
		return
	# Rest-локалы + родители скина (имена mixamorig_).
	var rest: Dictionary = {}
	var bone_idx: Dictionary = {}
	for i in skel.get_bone_count():
		var bn: String = skel.get_bone_name(i).replace("mixamorig1_", "mixamorig_")
		rest[bn] = skel.get_bone_rest(i)
		bone_idx[bn] = i
	var parent_name: Dictionary = {}
	for bn in bone_idx:
		var pi: int = skel.get_bone_parent(bone_idx[bn])
		parent_name[bn] = skel.get_bone_name(pi).replace("mixamorig1_", "mixamorig_") if pi >= 0 else ""
	player.free()

	var lib = load(LIB_PATH)
	for clip in CLIPS:
		var anim: Animation = lib.get_animation(LIB_NAME[clip]) if lib.has_animation(LIB_NAME[clip]) else null
		var rf := FileAccess.open("%s/%s/root_positions.f32" % [BASE, clip], FileAccess.READ)
		var ff := FileAccess.open("%s/%s/local_rotations_xyzw.f32" % [BASE, clip], FileAccess.READ)
		if anim == null or rf == null or ff == null:
			print("POSE SKIP: ", clip)
			continue
		var roots: PackedFloat32Array = rf.get_buffer(rf.get_length()).to_float32_array()
		var rots: PackedFloat32Array = ff.get_buffer(ff.get_length()).to_float32_array()
		rf.close()
		ff.close()
		var frames := rots.size() / (SOMA_NAMES.size() * 4)
		for frac in [0.0, 0.5, 0.99]:
			var k := int(frames * frac)
			k = mini(k, frames - 1)
			var g_soma: Dictionary = {}
			_soma_fk(roots, rots, k, g_soma)
			var t: float = minf(k / 30.0, anim.length - 0.001)
			var g_skin: Dictionary = {}
			_skin_fk(anim, rest, parent_name, t, g_skin)
			print("POSE %s t=%.2f RAW  L(%s) R(%s)" % [clip, t, _f(g_soma["LeftHand"].origin), _f(g_soma["RightHand"].origin)])
			print("POSE %s t=%.2f SKIN L(%s) R(%s)" % [clip, t, _f(g_skin["mixamorig_LeftHand"].origin), _f(g_skin["mixamorig_RightHand"].origin)])
	quit(0)

func _f(v: Vector3) -> String:
	return "x%+.2f y%.2f z%+.2f" % [v.x, v.y, v.z]

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
func _skin_fk(anim: Animation, rest: Dictionary, parent_name: Dictionary, t: float, g: Dictionary) -> void:
	var locals: Dictionary = {}
	for bn in rest:
		locals[bn] = rest[bn]
	for t_i in anim.get_track_count():
		if anim.track_get_type(t_i) != Animation.TYPE_ROTATION_3D:
			continue
		var bn := str(anim.track_get_path(t_i)).get_slice(":", 1)
		if locals.has(bn):
			var q: Quaternion = anim.rotation_track_interpolate(t_i, t)
			locals[bn].basis = Basis(q)
	# Топ-даун по иерархии (порядок словаря = порядок костей скелета = родитель раньше).
	for bn in locals:
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
