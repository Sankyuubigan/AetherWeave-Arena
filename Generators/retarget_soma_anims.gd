extends SceneTree
## Ретаргет НЕЙРО-анимаций kimodo.cpp (SOMA 30 суставов) → mixamorig_ (скин Ch24).
## Источник: D:/nn/kimodo.cpp/out/<clip>/root_positions.f32 (frames×3, метры,
## Y-up, лицо +Z) + local_rotations_xyzw.f32 (frames×30×4, XYZW, локальные),
## fps=30. Скелет SOMA30 — копия из kimodo.cpp src/skeleton.hpp (T-поза,
## rest-повороты = identity, офсеты родитель-локальные).
##
## Математика та же, что починила UAL-ретаргет (инвариант 87°→1.47°):
## C_m = mix_rest(m) · G_ref(m)^-1, где G_ref — нейтраль ИСТОЧНИКА = кадр 0
## клипа (полный FK: root_positions + кваты; в нейтрали q_local = rest
## ЛОКАЛЬНО точно, позиция Hips = rest_скина + дельты root_positions).
## ⚠ Нейтраль от аналитической T-позы НЕЛЬЗЯ: офсеты не содержат высоты
## корня (~0.97 м в отдельном канале) — C_Hips двоил её, фигура «прыгала
## наверх и висела» на каждом касте (баг 17.11.26, починен кадром-0).
##
## side_flip: если SOMA-«Left» на другой стороне X, чем mixamo-Left — пары
## свапаются автоматически (лог SIDE CHECK).
##
## Запуск:
## & "...Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/retarget_soma_anims.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const LIB_PATH := "res://Graphics/Animations/shared_animations.res"
const SOMA_DIR := "res://Graphics/Animations/neuro_soma"
const FPS := 30.0

## Нейро-клипы: имя в библиотеке → подкаталог out/. ЗЕРКАЛ НЕТ: конъюгация
## кватернионов (x,-y,-z,w) НЕ переводит rest левой кости в rest правой на
## mixamo-риге (тест поймал 176.7° на RightShoulder t=0 — «кукла» на _L).
## Лево/право-варианты генерируются НЕЙРОСЕТЬЮ отдельными промптами
## (pistol_shoot_l, cast_shoot_b), см. neuro_soma/prompts/.
const TASKS := {
	"Cast_Enter": "cast_enter",
	"Cast_Loop": "cast_loop",
	"Cast_Shoot": "cast_shoot",
	"Cast_Shoot_L": "cast_shoot_b",
	"Cast_Exit": "cast_exit",
	"Throw": "throw",
	"Pistol_Shoot": "pistol_shoot",
	"Pistol_Shoot_L": "pistol_shoot_l",
}

## SOMA30 → mixamorig. Листья SOMA (Jaw, глаза, кончики пальцев) не мапятся.
const BONE_MAP := {
	"Hips": "mixamorig_Hips",
	"Spine1": "mixamorig_Spine",
	"Spine2": "mixamorig_Spine1",
	"Chest": "mixamorig_Spine2",
	"Neck1": "mixamorig_Neck",
	"Neck2": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftArm": "mixamorig_LeftArm",
	"LeftForeArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder",
	"RightArm": "mixamorig_RightArm",
	"RightForeArm": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"LeftLeg": "mixamorig_LeftUpLeg",
	"LeftShin": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToeBase": "mixamorig_LeftToeBase",
	"RightLeg": "mixamorig_RightUpLeg",
	"RightShin": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
	"RightToeBase": "mixamorig_RightToeBase",
}

## Скелет SOMA30 (дословная копия src/skeleton.hpp kimodo.cpp).
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

var mix_rest: Dictionary = {}   # mixamorig имя -> глоб rest скина (player.tscn, SSOT)
var g_ref: Dictionary = {}      # SOMA сустав -> глоб T-позы (identity-повороты)
var side_flip := false          # SOMA-«Left» на другой стороне X, чем mixamo-Left

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mix_root = load(PLAYER_SCENE).instantiate()
	var mix_skel = _find_skeleton(mix_root)
	if mix_skel == null:
		_fail("нет Skeleton3D в player.tscn")
		return
	for i in mix_skel.get_bone_count():
		var bn: String = mix_skel.get_bone_name(i).replace("mixamorig1_", "mixamorig_")
		mix_rest[bn] = mix_skel.get_bone_global_rest(i)
	mix_root.free()
	_build_soma_neutral()

	var soma_left_x: float = g_ref["LeftHand"].origin.x
	var mix_left_x: float = mix_rest["mixamorig_LeftHand"].origin.x
	side_flip = signf(soma_left_x) != signf(mix_left_x)
	print("SIDE CHECK: soma LeftHand.x=%.3f mix LeftHand.x=%.3f -> side_flip=%s" % [soma_left_x, mix_left_x, side_flip])

	var lib = load(LIB_PATH)
	if lib == null or not (lib is AnimationLibrary):
		_fail("не загрузилась библиотека " + LIB_PATH)
		return

	var ok := 0
	for out_name in TASKS:
		var new_anim = _retarget_one(TASKS[out_name], out_name)
		if new_anim == null:
			continue
		if lib.has_animation(out_name):
			lib.remove_animation(out_name)
		lib.add_animation(out_name, new_anim)
		print("RETARGET: %s ← soma/%s (%.2f с, треков %d)%s" % [out_name, TASKS[out_name], new_anim.length, new_anim.get_track_count(), " [LOOP]" if new_anim.loop_mode != Animation.LOOP_NONE else ""])
		ok += 1

	if ok == 0:
		_fail("ни одной анимации")
		return
	if ok < TASKS.size():
		print("RETARGET WARN: успешных %d из %d (недостающие клипы не сгенерены)" % [ok, TASKS.size()])
	var err := ResourceSaver.save(lib, LIB_PATH)
	if err != OK:
		_fail("save err " + str(err))
		return
	print("Saved: " + LIB_PATH)
	quit(0)

## Читает .f32 клипа и ретаргетит → Animation (или null, если клипа нет).
func _retarget_one(clip_dir: String, out_name: String) -> Animation:
	var rot_file := FileAccess.open(SOMA_DIR + "/" + clip_dir + "/local_rotations_xyzw.f32", FileAccess.READ)
	var root_file := FileAccess.open(SOMA_DIR + "/" + clip_dir + "/root_positions.f32", FileAccess.READ)
	if rot_file == null or root_file == null:
		print("RETARGET SKIP: нет .f32 в %s/%s (сначала kmd-generate)" % [SOMA_DIR, clip_dir])
		return null
	var rots: PackedFloat32Array = rot_file.get_buffer(rot_file.get_length()).to_float32_array()
	var roots: PackedFloat32Array = root_file.get_buffer(root_file.get_length()).to_float32_array()
	rot_file.close()
	root_file.close()
	var nj := SOMA_NAMES.size()
	var frames := rots.size() / (nj * 4)
	if frames == 0 or roots.size() != frames * 3:
		_fail("битые .f32 в " + clip_dir)
		return null

	# Шов лупа: зонд показал до 43° на кисти между кадром 0 и последним.
	# Кроссфейд хвоста на ОБРАТНУЮ голову: out[L+i] = slerp(M(L+i), M(N-1-i), w),
	# w→1 ⇒ последний кадр = M(0) ТОЧНО (нулевой поп на завороте; обратный
	# микро-путь кисти за 0.33с канала незаметен). Цели берутся из головы
	# (< L), мутация in-place безопасна.
	if out_name == "Cast_Loop" and frames >= 12:
		var n_fade := mini(10, frames / 4)
		var head := frames - n_fade
		for i in n_fade:
			var w := (i + 1) / float(n_fade)
			for j in nj:
				var dst := (head + i) * nj * 4 + j * 4
				var src := (n_fade - 1 - i) * nj * 4 + j * 4
				var qa := Quaternion(rots[dst], rots[dst + 1], rots[dst + 2], rots[dst + 3])
				var qb := Quaternion(rots[src], rots[src + 1], rots[src + 2], rots[src + 3])
				var qs := qa.slerp(qb, w)
				rots[dst] = qs.x
				rots[dst + 1] = qs.y
				rots[dst + 2] = qs.z
				rots[dst + 3] = qs.w
			for a in 3:
				var dpos := (head + i) * 3 + a
				roots[dpos] = lerpf(roots[dpos], roots[(n_fade - 1 - i) * 3 + a], w)
		print("  LOOP FADE: хвост %d кадров → точный шов (последний кадр = кадр 0)" % n_fade)

	# Эффективная карта: ключ = СОМЕДСКИЙ сустав в пространстве данных
	# (side_flip свапает имена), значение = целевая кость.
	var emap: Dictionary = {}
	for m in BONE_MAP:
		var key: String = _mirror_name(m) if side_flip else m
		emap[key] = {"target": BONE_MAP[m], "soma": m}

	# Нейтраль клипа = кадр 0 ЭТОГО клипа (философия UAL-фикса «куклы»).
	# ЛОВЕШКА, на которой персонаж «прыгал наверх»: аналитическая T-поза
	# SOMA имеет Hips в (0,0,0) — высота бёдер (~0.97 м) живёт в ОТДЕЛЬНОМ
	# канале root_positions и в офсеты НЕ входит. C_Hips от такой нейтрали
	# ДВОИЛ высоту (rest_скина + полные 0.97 м) — фигура взлетала на касте.
	# Кадр 0 содержит и высоту, и стартовую позу ⇒ на t=0 выход = rest
	# скина точно, позиция бёдер — только дельты root_positions.
	var g0: Dictionary = {}
	_soma_fk(roots, rots, 0, g0)

	# C_m и родители (ключи — в пространстве данных).
	var C: Dictionary = {}
	var parent_key: Dictionary = {}
	for key in emap:
		var soma_name: String = emap[key]["soma"]
		C[key] = mix_rest[emap[key]["target"]] * g0[soma_name].inverse()
		var pi: int = SOMA_PARENTS[SOMA_NAMES.find(soma_name)]
		var pname: String = SOMA_NAMES[pi] if pi >= 0 else ""
		parent_key[key] = (_mirror_name(pname) if side_flip else pname)

	var out := Animation.new()
	out.length = frames / FPS
	out.loop_mode = Animation.LOOP_LINEAR if out_name == "Cast_Loop" else Animation.LOOP_NONE

	var rot_track: Dictionary = {}  # key -> индекс трека
	var pos_track := -1
	var g: Dictionary = {}          # SOMA глобальные FK кадра
	var t_out: Dictionary = {}      # key -> глоб в целевом пространстве
	var hand_lo := Vector3(1e9, 1e9, 1e9)
	var hand_hi := Vector3(-1e9, -1e9, -1e9)
	var hips_lo := 1e9
	var hips_hi := -1e9
	var hips_rest_y: float = mix_rest["mixamorig_Hips"].origin.y

	for k in frames:
		var t := k / FPS
		_soma_fk(roots, rots, k, g)
		var lh: Vector3 = g["LeftHand"].origin
		var rh: Vector3 = g["RightHand"].origin
		hand_lo = hand_lo.min(lh).min(rh)
		hand_hi = hand_hi.max(lh).max(rh)
		# Топ-даун (SOMA_NAMES упорядочены родитель-раньше-потомка; BONE_MAP тоже).
		for key in emap:
			var soma_name: String = emap[key]["soma"]
			var pk: String = parent_key[key]
			var g_soma: Transform3D = g[soma_name]
			var c_self: Transform3D = C[key]
			var gt: Transform3D
			if pk == "" or not C.has(pk):
				gt = c_self * g_soma
			else:
				gt = (C[pk] * g[pk]).inverse() * c_self * g_soma
			t_out[key] = gt
		for key in emap:
			if not rot_track.has(key):
				rot_track[key] = out.add_track(Animation.TYPE_ROTATION_3D)
				out.track_set_path(rot_track[key], NodePath("Skeleton3D:" + emap[key]["target"]))
			out.track_insert_key(rot_track[key], t, t_out[key].basis.get_rotation_quaternion().normalized())
			if emap[key]["soma"] == "Hips":
				if pos_track < 0:
					pos_track = out.add_track(Animation.TYPE_POSITION_3D)
					out.track_set_path(pos_track, NodePath("Skeleton3D:" + emap[key]["target"]))
				var o: Vector3 = t_out[key].origin
				hips_lo = minf(hips_lo, o.y)
				hips_hi = maxf(hips_hi, o.y)
				out.track_insert_key(pos_track, t, o)

	if out.get_track_count() == 0:
		print("RETARGET FAIL: пустой выход для " + out_name)
		return null
	# Инвариант высоты (регресс «прыгает наверх»): бёдра не должны уходить
	# от rest-высоты скина дальше 0.15 м — иначе клип левитирует.
	if maxf(absf(hips_lo - hips_rest_y), absf(hips_hi - hips_rest_y)) > 0.15:
		print("  HIPS WARN: y %.2f..%.2f при rest %.2f — клип левитирует!" % [hips_lo, hips_hi, hips_rest_y])
	else:
		print("  HIPS OK: y %.2f..%.2f (rest %.2f)" % [hips_lo, hips_hi, hips_rest_y])
	print("  HANDS: y %.2f..%.2f z %.2f..%.2f" % [hand_lo.y, hand_hi.y, hand_lo.z, hand_hi.z])
	return out

## Глобальный FK SOMA в кадре: G = G_parent · T(offset) · R(q);
## корень Hips — позиция из root_positions кадра.
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

## Аналитическая T-поза SOMA — ТОЛЬКО для side-чека (знак X кисти);
## нейтраль ретаргета — кадр 0 клипа (см. _retarget_one).
func _build_soma_neutral() -> void:
	g_ref.clear()
	for j in SOMA_NAMES.size():
		var local := Transform3D(Basis.IDENTITY, SOMA_OFFSETS[j])
		var pi: int = SOMA_PARENTS[j]
		g_ref[SOMA_NAMES[j]] = g_ref[SOMA_NAMES[pi]] * local if pi >= 0 else local
	print("NEUTRAL REF: %d суставов SOMA (T-поза из офсетов)" % g_ref.size())

static func _mirror_name(n: String) -> String:
	return n.replace("Left", "@TMP@").replace("Right", "Left").replace("@TMP@", "Right")

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null

func _fail(msg: String) -> void:
	print("SOMA RETARGET FAIL: ", msg)
	quit(1)
