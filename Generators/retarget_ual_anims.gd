extends SceneTree
## Ретаргет каст-анимаций UAL (Unity/UE Mannequin) → mixamorig_ (скин Ch24).
## v4 (17.11.26): мировая дельта от T-позы, ПЕРЕЗАРЯЖЕННАЯ через S.
## Диагноз v3 (зонд probe_bone_trace/probe_apply_pred): выход v3 был точен
## (рантайм == C_b·A_b до миллиметра), но C_b рук малы (5-16°) — кости рук
## обоих ригов конвентно выровнены, и мировые дельты gT^-1·A (живут в Z-up
## мире UAL) прикладывались в Y-up мир скина БЕЗ конвертации осей: «вверх»
## источника (+Z chain) читался как «вперёд» скина (+Z skin) → сторона/фронт
## менялись местами («зеркало»: источник левую — скин правую).
## Формула v4 (семантика работающего SOMA-ретаргета R=Δ·R_rest + конвертация):
##   R_out(b,t) = S·(A_b·gT_b^-1)·S^-1 · mix_rest_b
##   pelvis     = mix_rest.origin + S·(A_pelvis.origin − gT.origin)
## где S = rotX(−90°) (chain: up=+Z, fwd=−Y, right=−X → skin: up=+Y, fwd=+Z,
## right=−X); T-позы ригов совпадают под S (оверли рук/стоп проверен зондами).
## Нейтраль = эталонная T-поза пака (клип A_TPose), T↔T-пара.
## Выход: ual_casts_test.res (тестовая библиотека; shared_animations.res
## занят нейро-клипами, ждущими вердикта юзера).
##
## Запуск:
## & "...Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/retarget_ual_anims.gd

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const UAL2 := "res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unity/UAL2_Standard.fbx"
## SSOT rest-поз цели — СКИН игрока (player.tscn), НЕ Idle.fbx: rest-фреймы
## Idle.fbx расходятся со скином до ~90° на кистях (зонд probe_retarget,
## вердикт юзера «перекашивает как куклу») — дельты от Idle давали вывихи.
const PLAYER_SCENE := "res://Scenes/player.tscn"
## v3 (17.11.26): вывод в ТЕСТОВУЮ библиотеку — shared_animations.res занят
## нейро-клипами (вердикт юзера по ним ещё не дан), не трогаем.
const LIB_PATH := "res://Graphics/Animations/ual_casts_test.res"

## Анимации к ретаргету: имя в библиотеке → [файл, имя в UAL, зеркало]
## Зеркало (вердикт юзера: сердечко кастует попеременно лево/право): свап
## Left↔Right в именах костей + сопряжение кватернионов (w,x,-y,-z) +
## X-флип позиции pelvis — стандартная техника зеркалирования скелеток.
## v3: зеркала _L выпилены (конъюгация не переводит rest Left→Right — баг
## Задачи 26); юзер просил каст ПОД ПРАВУЮ руку — берём правые клипы.
const TASKS := {
	"Cast_Enter": [UAL1, "Armature|Spell_Simple_Enter", false],
	"Cast_Loop": [UAL1, "Armature|Spell_Simple_Idle_Loop", false],
	"Cast_Shoot": [UAL1, "Armature|Spell_Simple_Shoot", false],
	"Cast_Exit": [UAL1, "Armature|Spell_Simple_Exit", false],
	"Throw": [UAL2, "Armature|OverhandThrow", false],
	"Pistol_Shoot": [UAL1, "Armature|Pistol_Shoot", false],
	# Двуручный толчок для лазера (beam). ОТДЕЛЬНОЕ имя, чтобы не задевать
	# сердечки: они играют "Cast_Push" (SOMA) — юзер подберёт анимацию сам.
	"Beam_Push": [UAL1, "Armature|Push_Loop", false],
	# Мечевые свинги для Энергетического клинка (Q19): UAL2 Sword_Regular_A/B —
	# короткие праворукие взмахи (0.43/0.53 с); Blade_Swing_A — базовый удар.
	"Blade_Swing_A": [UAL2, "Armature|Sword_Regular_A", false],
	"Blade_Swing_B": [UAL2, "Armature|Sword_Regular_B", false],
}
const LOOPED := ["Cast_Loop"]

## Mannequin → mixamorig. Листья (_leaf), root и прочее — намеренно нет.
const BONE_MAP := {
	"pelvis": "mixamorig_Hips",
	"spine_01": "mixamorig_Spine",
	"spine_02": "mixamorig_Spine1",
	"spine_03": "mixamorig_Spine2",
	"neck_01": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"clavicle_l": "mixamorig_LeftShoulder",
	"upperarm_l": "mixamorig_LeftArm",
	"lowerarm_l": "mixamorig_LeftForeArm",
	"hand_l": "mixamorig_LeftHand",
	"clavicle_r": "mixamorig_RightShoulder",
	"upperarm_r": "mixamorig_RightArm",
	"lowerarm_r": "mixamorig_RightForeArm",
	"hand_r": "mixamorig_RightHand",
	"thigh_l": "mixamorig_LeftUpLeg",
	"calf_l": "mixamorig_LeftLeg",
	"foot_l": "mixamorig_LeftFoot",
	"ball_l": "mixamorig_LeftToeBase",
	"thigh_r": "mixamorig_RightUpLeg",
	"calf_r": "mixamorig_RightLeg",
	"foot_r": "mixamorig_RightFoot",
	"ball_r": "mixamorig_RightToeBase",
}

func _init() -> void:
	call_deferred("_run")

var mix_rest: Dictionary = {}      # "mixamorig_Hips" -> Transform3D (глоб rest скина)
var g_refs: Dictionary = {}        # путь FBX -> {кость -> глоб НЕЙТРАЛИ (A_TPose)}
var g_ref: Dictionary = {}         # нейтраль ТЕКУЩЕГО исходника (см. _retarget_one)
var ual_skel: Skeleton3D
var ual_anim: Animation
var ual_tracks: Dictionary = {}    # bone name -> {"rot": idx, "pos": idx}

func _run() -> void:
	var mix_root = load(PLAYER_SCENE).instantiate()
	var mix_skel = find_skeleton(mix_root)
	if mix_skel == null:
		_fail("нет Skeleton3D в player.tscn")
		return
	for i in mix_skel.get_bone_count():
		var bn: String = mix_skel.get_bone_name(i).replace("mixamorig1_", "mixamorig_")
		mix_rest[bn] = mix_skel.get_bone_global_rest(i)
	mix_root.free()
	# Нейтраль строится per-исходник в _retarget_one (кэш g_refs).

	var lib = load(LIB_PATH)
	if lib == null:
		print("RETARGET: библиотеки нет — создаём новую " + LIB_PATH)
		lib = AnimationLibrary.new()
	elif not (lib is AnimationLibrary):
		_fail("не библиотека: " + LIB_PATH)
		return

	var ok := 0
	for out_name in TASKS:
		var src_path: String = TASKS[out_name][0]
		var src_anim: String = TASKS[out_name][1]
		var mirror: bool = TASKS[out_name][2]
		var new_anim = _retarget_one(src_path, src_anim, out_name, mirror)
		if new_anim == null:
			continue
		if lib.has_animation(out_name):
			lib.remove_animation(out_name)
		lib.add_animation(out_name, new_anim)
		print("RETARGET: %s ← %s (%.2f с, треков %d)%s" % [out_name, src_anim, new_anim.length, new_anim.get_track_count(), " [LOOP]" if out_name in LOOPED else ""])
		ok += 1

	if ok < TASKS.size():
		print("RETARGET: успешных %d из %d" % [ok, TASKS.size()])
	if ok == 0:
		_fail("ни одной анимации")
		return
	var err := ResourceSaver.save(lib, LIB_PATH)
	if err != OK:
		_fail("save err " + str(err))
		return
	print("Saved: " + LIB_PATH)
	quit(0)

## Ретаргет одной анимации → Animation (или null). mirror — зеркалить лево/право.
func _retarget_one(src_path: String, src_anim_name: String, out_name: String, mirror: bool) -> Animation:
	var root = load_fbx_scene(src_path)
	if root == null:
		print("RETARGET FAIL: не загрузился ", src_path)
		return null
	ual_skel = find_skeleton(root)
	var ap = find_animation_player(root)
	if ual_skel == null or ap == null:
		print("RETARGET FAIL: нет скелета/аниматора в ", src_path)
		return null
	var fbx_lib = ap.get_animation_library("")
	ual_anim = _find_anim(fbx_lib, src_anim_name)
	if ual_anim == null:
		print("RETARGET FAIL: нет анимации ", src_anim_name)
		return null

	# Индекс треков mannequin по именам костей
	_index_tracks()

	# Нейтраль = эталонная T-поза ПАКА (клип A_TPose, есть в обоих файлах).
	## v3, корень прошлых провалов: нейтралью был кадр 0 Enter (расслабленная
	## стойка) → дельта «от стойки», приложенная к T-позе скина, давала
	## систематический сдвиг всех поз + T-позу-вспышку каждый раз, когда клип
	## проходит около нейтрали («всё кривые, ужасно»). T↔T-пара (как в
	## работающем SOMA-ретаргете) даёт чистые мировые дельты движения.
	## t=0 выходного клипа теперь ЕСТЕСТВЕННЫЙ (расслабленный), НЕ rest —
	## инвариант «t=0 = rest» для UAL больше не гейт (он цементировал баг).
	if not g_refs.has(src_path):
		_build_neutral_ref(src_path)
	g_ref = g_refs[src_path]

	# v4: W-дельты. S = rotX(−90°): chain (up=+Z, fwd=−Y, right=−X) → skin
	# (up=+Y, fwd=+Z, right=−X). T-позы ригов совпадают под S (оверли зондов:
	# S·gT(hand_r)=(−0.74,1.44,−0.07) ≈ rest RightHand (−0.712,1.30,−0.012)).
	var S_q := Quaternion(Vector3(1, 0, 0), deg_to_rad(-90.0))
	var S_qi := S_q.inverse()
	var W_data: Dictionary = {}  # ual bone -> {mix: Quaternion, gT: Quaternion}
	var name2idx: Dictionary = {}
	for i in ual_skel.get_bone_count():
		name2idx[ual_skel.get_bone_name(i)] = i
	for m in BONE_MAP:
		if not mix_rest.has(BONE_MAP[m]) or not g_ref.has(m):
			print("RETARGET WARN: нет пары костей ", m, "→", BONE_MAP[m])
			continue
		W_data[m] = {
			"mix": (mix_rest[BONE_MAP[m]] as Transform3D).basis.get_rotation_quaternion(),
			"gT": (g_ref[m] as Transform3D).basis.get_rotation_quaternion(),
		}
	var parent_map: Dictionary = {}
	for m in W_data:
		var pi: int = ual_skel.get_bone_parent(name2idx[m])
		var pname: String = ual_skel.get_bone_name(pi) if pi >= 0 else ""
		parent_map[m] = pname if W_data.has(pname) else ""

	var out := Animation.new()
	out.length = ual_anim.length
	out.loop_mode = Animation.LOOP_LINEAR if out_name in LOOPED else Animation.LOOP_NONE

	for m in W_data:
		var xname: String = _mirror_name(BONE_MAP[m]) if mirror else BONE_MAP[m]
		var d: Dictionary = ual_tracks.get(m, {})
		var mix_q: Quaternion = W_data[m]["mix"]
		var gt_qi: Quaternion = (W_data[m]["gT"] as Quaternion).inverse()
		if d.has("rot"):
			var tr: int = d["rot"]
			var kc := ual_anim.track_get_key_count(tr)
			var ntr := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(ntr, NodePath("Skeleton3D:" + xname))
			var pm_name: String = parent_map[m]
			for k in kc:
				var t := ual_anim.track_get_key_time(tr, k)
				# W_b = S·(A_b·gT_b⁻¹)·S⁻¹·mix_rest_b — мировая дельта от T-позы,
				# перезаряженная в мир скина; out_global рантайма = W_b (индукция
				# по локальной конверсии ниже).
				var a_q: Quaternion = _mannequin_global(name2idx[m], t).basis.get_rotation_quaternion()
				var w: Quaternion = (S_q * (a_q * gt_qi) * S_qi * mix_q).normalized()
				var q: Quaternion
				if pm_name == "":
					# pelvis: родитель вне карты (UAL root) — Hips корневая кость
					# скина: её глобаль = трек-локаль
					q = w
				else:
					var a_p: Quaternion = _mannequin_global(name2idx[pm_name], t).basis.get_rotation_quaternion()
					var wd_p: Dictionary = W_data[pm_name]
					var w_p: Quaternion = (S_q * (a_p * (wd_p["gT"] as Quaternion).inverse()) * S_qi * (wd_p["mix"] as Quaternion)).normalized()
					q = (w_p.inverse() * w).normalized()
				if mirror:
					q = Quaternion(q.x, -q.y, -q.z, q.w)
				out.track_insert_key(ntr, t, q.normalized())
		if m == "pelvis" and d.has("pos"):
			var tr2: int = d["pos"]
			var kc2 := ual_anim.track_get_key_count(tr2)
			var ntr2 := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(ntr2, NodePath("Skeleton3D:" + xname))
			var mix_o: Vector3 = (mix_rest[BONE_MAP["pelvis"]] as Transform3D).origin
			var gt_o: Vector3 = (g_ref["pelvis"] as Transform3D).origin
			for k in kc2:
				var t2 := ual_anim.track_get_key_time(tr2, k)
				var g_o: Vector3 = _mannequin_global(name2idx["pelvis"], t2).origin
				var o: Vector3 = mix_o + S_q * (g_o - gt_o)
				if mirror:
					o = Vector3(-o.x, o.y, o.z)
				out.track_insert_key(ntr2, t2, o)
	root.queue_free()
	if out.get_track_count() == 0:
		print("RETARGET FAIL: пустой выход для ", out_name)
		return null
	return out

## Референс-поза mannequin = кадр 0 клипа A_TPose (эталонная T-поза пака).
## v3 (было: t=0 Spell_Simple_Enter — расслабленная стойка; дельты от неё
## ломали позы mid-клипа, см. коммент в _retarget_one). BIND-rest тоже не
## годится: у UAL bind-фреймы рук развёрнуты на 70–86° против авторских
## (probe3), дельты от bind дают вывихнутые позы («перекашивает как куклу»).
func _build_neutral_ref(src_path: String) -> void:
	# Хелперы (_mannequin_global/_index_tracks) держат состояние в членах:
	# нейтраль грузит СВОЮ сцену, поэтому члены задачи сохраняем/возвращаем.
	var saved_skel := ual_skel
	var saved_anim := ual_anim
	# Dictionary — ССЫЛОЧНЫЙ тип: без duplicate() saved_tracks разделяет объект
	# с ual_tracks, и _index_tracks() нейтрали стирает индекс задачи.
	var saved_tracks: Dictionary = ual_tracks.duplicate(true)
	var root = load_fbx_scene(src_path)
	if root == null:
		_fail("нет исходника для референс-позы: " + src_path)
		return
	ual_skel = find_skeleton(root)
	var ap = find_animation_player(root)
	if ual_skel == null or ap == null:
		_fail("нет скелета/аниматора для референса: " + src_path)
		return
	ual_anim = _find_anim(ap.get_animation_library(""), "Armature|A_TPose")
	if ual_anim == null:
		_fail("нет A_TPose для референса в " + src_path)
		return
	_index_tracks()
	g_ref.clear()
	for i in ual_skel.get_bone_count():
		g_ref[ual_skel.get_bone_name(i)] = _mannequin_global(i, 0.0)
	g_refs[src_path] = g_ref.duplicate(true)
	root.free()
	ual_skel = saved_skel
	ual_anim = saved_anim
	ual_tracks = saved_tracks
	print("NEUTRAL REF: %d костей от A_TPose (%s)" % [g_ref.size(), src_path.get_file()])

func _find_anim(fbx_lib: AnimationLibrary, src_anim_name: String) -> Animation:
	var a = fbx_lib.get_animation(src_anim_name) \
			if fbx_lib and fbx_lib.has_animation(src_anim_name) else null
	if a == null:
		# FBX может переименовать ("Armature|" теряется) — ищем по хвосту
		for n in fbx_lib.get_animation_list():
			if String(n).ends_with(String(src_anim_name).split("|")[1]):
				a = fbx_lib.get_animation(n)
				break
	return a

func _index_tracks() -> void:
	ual_tracks.clear()
	for i in ual_anim.get_track_count():
		var p := str(ual_anim.track_get_path(i))
		if not ":" in p:
			continue
		var bone := p.get_slice(":", p.get_slice_count(":") - 1)
		if not ual_tracks.has(bone):
			ual_tracks[bone] = {}
		if ual_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			ual_tracks[bone]["rot"] = i
		elif ual_anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			ual_tracks[bone]["pos"] = i

## Глобальный анимированный трансформ кости mannequin в момент t (рекурсия).
func _mannequin_global(bone_idx: int, t: float) -> Transform3D:
	var parent := ual_skel.get_bone_parent(bone_idx)
	var pf := Transform3D.IDENTITY if parent < 0 else _mannequin_global(parent, t)
	var local := ual_skel.get_bone_rest(bone_idx)
	var tn := ual_skel.get_bone_name(bone_idx)
	if ual_tracks.has(tn):
		var d: Dictionary = ual_tracks[tn]
		if d.has("rot"):
			local.basis = Basis(_rot_at(d["rot"], t))
		if d.has("pos"):
			local.origin = _pos_at(d["pos"], t)
	return pf * local

func _rot_at(tr: int, t: float) -> Quaternion:
	var kc := ual_anim.track_get_key_count(tr)
	if kc == 0:
		return Quaternion.IDENTITY
	if t <= ual_anim.track_get_key_time(tr, 0):
		return ual_anim.track_get_key_value(tr, 0)
	if t >= ual_anim.track_get_key_time(tr, kc - 1):
		return ual_anim.track_get_key_value(tr, kc - 1)
	for k in range(1, kc):
		var t1 := ual_anim.track_get_key_time(tr, k)
		if t <= t1:
			var t0 := ual_anim.track_get_key_time(tr, k - 1)
			var q0: Quaternion = ual_anim.track_get_key_value(tr, k - 1)
			var q1: Quaternion = ual_anim.track_get_key_value(tr, k)
			return q0.slerp(q1, (t - t0) / maxf(t1 - t0, 0.0001))
	return ual_anim.track_get_key_value(tr, kc - 1)

func _pos_at(tr: int, t: float) -> Vector3:
	var kc := ual_anim.track_get_key_count(tr)
	if kc == 0:
		return Vector3.ZERO
	if t <= ual_anim.track_get_key_time(tr, 0):
		return ual_anim.track_get_key_value(tr, 0)
	if t >= ual_anim.track_get_key_time(tr, kc - 1):
		return ual_anim.track_get_key_value(tr, kc - 1)
	for k in range(1, kc):
		var t1 := ual_anim.track_get_key_time(tr, k)
		if t <= t1:
			var t0 := ual_anim.track_get_key_time(tr, k - 1)
			var v0: Vector3 = ual_anim.track_get_key_value(tr, k - 1)
			var v1: Vector3 = ual_anim.track_get_key_value(tr, k)
			return v0.lerp(v1, (t - t0) / maxf(t1 - t0, 0.0001))
	return ual_anim.track_get_key_value(tr, kc - 1)

## Зеркальное имя кости: Left↔Right (через буфер от двойного свапа).
static func _mirror_name(n: String) -> String:
	return n.replace("Left", "@TMP@").replace("Right", "Left").replace("@TMP@", "Right")

func load_fbx_scene(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("FBXDocument error: %s" % error_string(err))
		return null
	return fbx_doc.generate_scene(state)

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = find_skeleton(c)
		if r:
			return r
	return null

static func find_animation_player(node: Node) -> AnimationPlayer:
	if not node:
		return null
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r = find_animation_player(c)
		if r:
			return r
	return null

func _fail(msg: String) -> void:
	print("RETARGET FAIL: ", msg)
	quit(1)
