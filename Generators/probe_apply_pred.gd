extends SceneTree
## ЖЕЛЕЗНЫЙ тест: (1) читаем глобальные ротации руки из СГЕНЕРИРОВАННОГО
## Cast_Loop на живом скине; (2) применяем PRED-глобали (C_b·A из источника)
## напрямую в живой скелет и смотрим, где оказываются кисти.
## Если (1) == PRED — рантайм = математика; вопрос закрывается в пользу C_b/нейтрали.
## Запуск: --headless -s res://Generators/probe_apply_pred.gd

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"

var skel: Skeleton3D
var anim: Animation
var tracks: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ── Скин ──
	var packed: PackedScene = load(PLAYER_SCENE)
	var player := packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var sks := player.find_children("*", "Skeleton3D", true, false)
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	var skin: Skeleton3D = sks[0]
	var ap: AnimationPlayer = aps[0]
	var extra = load(TEST_LIB)
	var def := ap.get_animation_library("")
	for an in extra.get_animation_list():
		if def.has_animation(an):
			def.remove_animation(an)
		def.add_animation(an, extra.get_animation(an))

	var CHAIN := {
		"mixamorig_RightShoulder": "clavicle_r", "mixamorig_RightArm": "upperarm_r",
		"mixamorig_RightForeArm": "lowerarm_r", "mixamorig_RightHand": "hand_r",
		"mixamorig_LeftShoulder": "clavicle_l", "mixamorig_LeftArm": "upperarm_l",
		"mixamorig_LeftForeArm": "lowerarm_l", "mixamorig_LeftHand": "hand_l",
	}

	# ── (1) Рантайм Cast_Loop t=0.03: глобальные ротации цепочек рук ──
	ap.play("Cast_Loop")
	ap.seek(0.03, true)
	await process_frame
	await process_frame
	print("=== RUNTIME Cast_Loop t=0.03 (глобальные ротации, град) ===")
	for nm in CHAIN:
		var i: int = skin.find_bone(nm)
		var g: Transform3D = skin.get_bone_global_pose(i)
		print("%-26s %s  pos %s" % [nm, _q(g.basis.get_rotation_quaternion()), g.origin])
	var hr := skin.find_bone("mixamorig_RightHand")
	var hl := skin.find_bone("mixamorig_LeftHand")
	print("RUNTIME кисти: R pos %s | L pos %s" % [
		skin.get_bone_global_pose(hr).origin, skin.get_bone_global_pose(hl).origin])

	# ── Источник: Idle f0 ──
	var A := _fk_ual("Armature|Spell_Simple_Idle_Loop")
	var gT := _fk_ual("Armature|A_TPose")

	# ── (2) PRED: применяем C_b·A как глобальные ротации в живой скелет ──
	print("=== APPLY PRED (C_b·A) в живой скелет, Idle f0 ===")
	for nm in CHAIN:
		var ual_b: String = CHAIN[nm]
		var i2: int = skin.find_bone(nm)
		var mix_rest: Transform3D = skin.get_bone_global_rest(i2)
		var cb: Transform3D = mix_rest * (gT[ual_b] as Transform3D).inverse()
		var r_pred: Quaternion = (cb * (A[ual_b] as Transform3D)).basis.get_rotation_quaternion()
		# конвертация глоб→локал: local = parent_global⁻¹ · desired_global
		var pi: int = skin.get_bone_parent(i2)
		var parent_g: Transform3D = skin.get_bone_global_pose(pi) if pi >= 0 else skin.global_transform
		var local_q: Quaternion = (parent_g.basis.get_rotation_quaternion().inverse() * r_pred).normalized()
		skin.set_bone_pose_rotation(i2, local_q)
	await process_frame
	await process_frame
	for nm in ["mixamorig_RightHand", "mixamorig_LeftHand"]:
		var i3: int = skin.find_bone(nm)
		print("APPLY %s pos %s" % [nm, skin.get_bone_global_pose(i3).origin])
	print("ОЖИДАНИЕ: если APPLY даёт ЛЕВУЮ высоко — математика верна и баг в .res;")
	print("если ПРАВУЮ высоко — баг в самом C_b·A (нейтраль/пары)")
	quit(0)

func _fk_ual(clip_path: String) -> Dictionary:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(UAL1.get_base_dir())
	var err = fbx_doc.append_from_file(UAL1, state)
	if err != OK:
		print("FBX ERR ", err)
		quit(1)
		return {}
	var scene = fbx_doc.generate_scene(state)
	skel = find_skeleton(scene)
	var ap = find_animation_player(scene)
	anim = ap.get_animation_library("").get_animation(clip_path)
	_index_tracks()
	var g := {}
	for bn in ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
			"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]:
		var i: int = skel.find_bone(bn)
		g[bn] = _mannequin_global(i, 0.0)
	scene.free()
	return g

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
