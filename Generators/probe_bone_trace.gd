extends SceneTree
## КОСТНЫЙ ТРАССИРОВЩИК зеркала: для левой/правой руки на Idle f0:
## 1) A_b — глобальная ротация источника (FK манекена)
## 2) R_pred = C_b·A_b — предсказание ретаргета (глобальная ротация скина)
## 3) FK скина с форсированными глобальными ротациями R_pred → позиции кистей
## Если предсказанные кисти «не как в рантайме» — баг в локальной конверсии;
## если «как в рантайме, но не как источник» — баг в C_b/нейтрали.
## Запуск: --headless -s res://Generators/probe_bone_trace.gd

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const PLAYER_SCENE := "res://Scenes/player.tscn"

var skel: Skeleton3D
var anim: Animation
var tracks: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ── Источник: FK Idle f0 ──
	var root = load_fbx_scene(UAL1)
	skel = find_skeleton(root)
	var ap = find_animation_player(root)
	anim = ap.get_animation_library("").get_animation("Armature|Spell_Simple_Idle_Loop")
	_index_tracks()
	var A := {}
	for bn in ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
			"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "pelvis"]:
		var i: int = skel.find_bone(bn)
		A[bn] = _mannequin_global(i, 0.0)
	print("SRC hand_r %s  hand_l %s" % [A["hand_r"].origin, A["hand_l"].origin])
	for bn in ["clavicle_r", "upperarm_r", "lowerarm_r", "clavicle_l", "upperarm_l", "lowerarm_l"]:
		print("SRC A(%s): %s" % [bn, _q(A[bn].basis.get_rotation_quaternion())])
	root.free()

	# ── Скин: rest + C_b ──
	var packed: PackedScene = load(PLAYER_SCENE)
	var player := packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var sks := player.find_children("*", "Skeleton3D", true, false)
	var skin: Skeleton3D = sks[0]
	var mix_rest := {}
	for i in skin.get_bone_count():
		mix_rest[skin.get_bone_name(i)] = skin.get_bone_global_rest(i)
	var C := {}
	for pair in [["clavicle_r", "mixamorig_RightShoulder"], ["upperarm_r", "mixamorig_RightArm"],
			["lowerarm_r", "mixamorig_RightForeArm"], ["hand_r", "mixamorig_RightHand"],
			["clavicle_l", "mixamorig_LeftShoulder"], ["upperarm_l", "mixamorig_LeftArm"],
			["lowerarm_l", "mixamorig_LeftForeArm"], ["hand_l", "mixamorig_LeftHand"]]:
		var ual_bone: String = pair[0]
		var mix_name: String = pair[1]
		C[ual_bone] = (mix_rest[mix_name] as Transform3D) * (A[ual_bone] as Transform3D).inverse()
		# ВНИМАНИЕ: здесь A — Idle-поза, НЕ нейтраль; C' = rest·Idle⁻¹ — диагностический
		# (для проверки направления отображения, не боевой C_b)

	# ── Предсказание: глобальные ротации R = C'·A (тождественное отображение
	# Idle→Idle при боевой C_b; здесь C'·A = rest_mix · A⁻¹ · A = rest_mix!) ──
	# То есть этот тест показывает: скин с глобальными ротациями = rest_mix
	# должен дать T-позу скина. Проверяем FK с форсом глобальных ротаций.
	# Для боевого теста заменяем A на Idle и C на C_b — но C_b требует g_T.
	# Здесь проще: FK скина с глобальными ротациями = rest_mix (T-поза),
	# затем с C_b·A, где C_b строим от A_TPose ниже.

	# ── Боевой C_b: нужна нейтраль A_TPose ──
	var root2 = load_fbx_scene(UAL1)
	skel = find_skeleton(root2)
	var ap2 = find_animation_player(root2)
	anim = ap2.get_animation_library("").get_animation("Armature|A_TPose")
	_index_tracks()
	var gT := {}
	for bn in ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
			"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]:
		var i2: int = skel.find_bone(bn)
		gT[bn] = _mannequin_global(i2, 0.0)
	var Cb := {}
	for pair in [["clavicle_r", "mixamorig_RightShoulder"], ["upperarm_r", "mixamorig_RightArm"],
			["lowerarm_r", "mixamorig_RightForeArm"], ["hand_r", "mixamorig_RightHand"],
			["clavicle_l", "mixamorig_LeftShoulder"], ["upperarm_l", "mixamorig_LeftArm"],
			["lowerarm_l", "mixamorig_LeftForeArm"], ["hand_l", "mixamorig_LeftHand"]]:
		Cb[pair[0]] = (mix_rest[pair[1]] as Transform3D) * (gT[pair[0]] as Transform3D).inverse()
	root2.free()

	# ── Предсказанные глобальные ротации для Idle f0 ──
	# A_b надо заново (skel сменился) — пересчитываем Idle
	root2 = load_fbx_scene(UAL1)
	skel = find_skeleton(root2)
	var ap3 = find_animation_player(root2)
	anim = ap3.get_animation_library("").get_animation("Armature|Spell_Simple_Idle_Loop")
	_index_tracks()
	var A2 := {}
	for bn in ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
			"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]:
		var i3: int = skel.find_bone(bn)
		A2[bn] = _mannequin_global(i3, 0.0)
	root2.free()

	for bn in ["upperarm_r", "lowerarm_r", "upperarm_l", "lowerarm_l"]:
		var rp: Quaternion = ((Cb[bn] as Transform3D) * (A2[bn] as Transform3D)).basis.get_rotation_quaternion()
		print("PRED %s: %s" % [bn, _q(rp)])

	# ── FK скина с форсированными глобальными ротациями ──
	# иерархия: Shoulder→Arm→ForeArm→Hand; глоб rot задан, позиция = parent_pos + parent_rot·rest_local_origin
	var chain_r := ["mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"]
	var chain_l := ["mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"]
	var force := {
		"mixamorig_RightShoulder": (Cb["clavicle_r"] as Transform3D * A2["clavicle_r"]).basis.get_rotation_quaternion(),
		"mixamorig_RightArm": (Cb["upperarm_r"] as Transform3D * A2["upperarm_r"]).basis.get_rotation_quaternion(),
		"mixamorig_RightForeArm": (Cb["lowerarm_r"] as Transform3D * A2["lowerarm_r"]).basis.get_rotation_quaternion(),
		"mixamorig_RightHand": (Cb["hand_r"] as Transform3D * A2["hand_r"]).basis.get_rotation_quaternion(),
		"mixamorig_LeftShoulder": (Cb["clavicle_l"] as Transform3D * A2["clavicle_l"]).basis.get_rotation_quaternion(),
		"mixamorig_LeftArm": (Cb["upperarm_l"] as Transform3D * A2["upperarm_l"]).basis.get_rotation_quaternion(),
		"mixamorig_LeftForeArm": (Cb["lowerarm_l"] as Transform3D * A2["lowerarm_l"]).basis.get_rotation_quaternion(),
		"mixamorig_LeftHand": (Cb["hand_l"] as Transform3D * A2["hand_l"]).basis.get_rotation_quaternion(),
	}
	for ch in [chain_r, chain_l]:
		var parent_pos := Vector3.ZERO
		var parent_rot := Quaternion.IDENTITY
		for nm in ch:
			var bi: int = skin.find_bone(nm)
			var rest_l: Transform3D = skin.get_bone_rest(bi)
			var gp: Vector3 = parent_pos + (parent_rot * rest_l.origin)
			var gr: Quaternion = force[nm]
			print("FK %s pos %s" % [nm, gp])
			parent_pos = gp
			parent_rot = gr
	print("ОЖИДАНИЕ: предсказанные LeftHand/RightHand должны повторить источник")
	print("(LeftHand высоко ~1.4 если источник поднимает левую)")
	quit(0)

func _q(q: Quaternion) -> String:
	var ang := rad_to_deg(q.get_angle())
	var ax := q.get_axis()
	if ang > 180.0:
		ang = 360.0 - ang
		ax = -ax
	if absf(ang) < 0.5:
		return "≈0"
	return "%5.1f° (%.2f,%.2f,%.2f)" % [ang, ax.x, ax.y, ax.z]

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)

func _index_tracks() -> void:
	tracks.clear()
	for i in anim.get_track_count():
		var p := str(anim.track_get_path(i))
		if not ":" in p:
			continue
		var bone := p.get_slice(":", p.get_slice_count(":") - 1)
		if not tracks.has(bone):
			tracks[bone] = {}
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			tracks[bone]["rot"] = i
		elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			tracks[bone]["pos"] = i

func _mannequin_global(bone_idx: int, t: float) -> Transform3D:
	var parent := skel.get_bone_parent(bone_idx)
	var pf := Transform3D.IDENTITY if parent < 0 else _mannequin_global(parent, t)
	var local := skel.get_bone_rest(bone_idx)
	var tn := skel.get_bone_name(bone_idx)
	if tracks.has(tn):
		var d: Dictionary = tracks[tn]
		if d.has("rot"):
			local.basis = Basis(_rot_at(d["rot"], t))
		if d.has("pos"):
			local.origin = _pos_at(d["pos"], t)
	return pf * local

func _rot_at(tr: int, t: float) -> Quaternion:
	var kc := anim.track_get_key_count(tr)
	if kc == 0:
		return Quaternion.IDENTITY
	if t <= anim.track_get_key_time(tr, 0):
		return anim.track_get_key_value(tr, 0)
	if t >= anim.track_get_key_time(tr, kc - 1):
		return anim.track_get_key_value(tr, kc - 1)
	for k in range(1, kc):
		var t1 := anim.track_get_key_time(tr, k)
		if t <= t1:
			var t0 := anim.track_get_key_time(tr, k - 1)
			var q0: Quaternion = anim.track_get_key_value(tr, k - 1)
			var q1: Quaternion = anim.track_get_key_value(tr, k)
			return q0.slerp(q1, (t - t0) / maxf(t1 - t0, 0.0001))
	return anim.track_get_key_value(tr, kc - 1)

func _pos_at(tr: int, t: float) -> Vector3:
	var kc := anim.track_get_key_count(tr)
	if kc == 0:
		return Vector3.ZERO
	if t <= anim.track_get_key_time(tr, 0):
		return anim.track_get_key_value(tr, 0)
	if t >= anim.track_get_key_time(tr, kc - 1):
		return anim.track_get_key_value(tr, kc - 1)
	for k in range(1, kc):
		var t1 := anim.track_get_key_time(tr, k)
		if t <= t1:
			var t0 := anim.track_get_key_time(tr, k - 1)
			var v0: Vector3 = anim.track_get_key_value(tr, k - 1)
			var v1: Vector3 = anim.track_get_key_value(tr, k)
			return v0.lerp(v1, (t - t0) / maxf(t1 - t0, 0.0001))
	return anim.track_get_key_value(tr, kc - 1)

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
