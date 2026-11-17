extends SceneTree
## ДИАГНОСТИКА осей/сторон ретаргета v3: почему выход зеркален источнику
## (скин поднимает правую, источник левую — плотная сверка).
## 1) Дельты A_TPose f0 vs Enter f0 / Idle f0 (валідность нейтрали: если
##    корень A_TPose повёрнут относительно рабочих клипов — C_b вбирает
##    чужой yaw и весь выход уходит в сторону/зеркало).
## 2) Константы C_b = mix_rest · g_T^-1 по цепочке (угол+ось, градусы).
## 3) Кисти в канонических осях: источник right=-x, up=+z, fwd=-y;
##    скин right=-x, up=+y, fwd=+z.
## Запуск: --headless -s res://Generators/probe_ual_axes.gd

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const PLAYER_SCENE := "res://Scenes/player.tscn"

var skel: Skeleton3D
var anim: Animation
var tracks: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root = load_fbx_scene(UAL1)
	if root == null:
		print("AX FAIL: нет сцены")
		quit(1)
		return
	skel = find_skeleton(root)
	var ap = find_animation_player(root)
	var lib = ap.get_animation_library("")

	var g_t := _fk_clip(lib, "A_TPose", 0.0)
	var g_e := _fk_clip(lib, "Spell_Simple_Enter", 0.0)
	var g_l := _fk_clip(lib, "Spell_Simple_Idle_Loop", 0.0)
	var g_p := _fk_clip(lib, "Pistol_Shoot", 0.0)

	var bones := ["pelvis", "spine_01", "spine_03", "neck_01", "Head",
		"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
		"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
		"thigh_r", "foot_r"]
	print("=== 1) A_TPose f0 vs рабочие клипы f0 (дельта в мире, град) ===")
	print("%-12s %22s %22s %22s" % ["кость", "vs Enter", "vs Idle_Loop", "vs Pistol"])
	for b in bones:
		if not g_t.has(b):
			continue
		var d_e := _delta_deg(g_t[b], g_e[b])
		var d_l := _delta_deg(g_t[b], g_l[b])
		var d_p := _delta_deg(g_t[b], g_p[b])
		print("%-12s %22s %22s %22s" % [b, d_e, d_l, d_p])

	print("=== 2) Происхождения (chain space) ===")
	for b in ["pelvis", "head", "hand_r", "hand_l", "foot_r", "foot_l"]:
		if g_t.has(b) and g_e.has(b):
			print("%-8s T%s  Enter%s" % [b, _v(g_t[b].origin), _v(g_e[b].origin)])

	print("=== 3) Константы C_b (mix_rest · g_T^-1), град ===")
	var mix_root = load(PLAYER_SCENE).instantiate()
	var mix_skel = find_skeleton(mix_root)
	for m in ["pelvis", "spine_01", "spine_03", "neck_01", "Head",
			"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
			"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]:
		var mix_name: String = _mix_name(m)
		var mi := mix_skel.find_bone(mix_name)
		if mi < 0 or not g_t.has(m):
			print("%-12s нет пары" % m)
			continue
		var mix_rest: Transform3D = mix_skel.get_bone_global_rest(mi)
		var c: Transform3D = mix_rest * (g_t[m] as Transform3D).inverse()
		print("%-12s %s" % [m, _axis_deg(c.basis.get_rotation_quaternion())])
	mix_root.free()

	print("=== 4) Кисти в канонических осях (right, up, fwd), Enter f0 vs Idle f0 ===")
	for b in ["hand_r", "hand_l"]:
		for pair in [[g_e, "Enter"], [g_l, "Idle"]]:
			var gg: Dictionary = pair[0]
			var tag: String = pair[1]
			var o: Vector3 = gg[b].origin
			var canon := Vector3(-o.x, o.z, -o.y)  # right, up, fwd
			print("%s %s: right%+.2f up%.2f fwd%+.2f" % [b, tag, canon.x, canon.y, canon.z])

	# ── 5) Куда смотрит фигура: fwd = up × (правое плечо − левое) ──
	# Источник (chain space, up=+Z): fwd = +Z × (clav_r − clav_l).
	print("=== 5) Стороны/фасинг ===")
	var cr: Vector3 = (g_t["clavicle_r"] as Transform3D).origin
	var cl: Vector3 = (g_t["clavicle_l"] as Transform3D).origin
	var fwd_u := Vector3(0, 0, 1).cross(cr - cl).normalized()
	print("SRC A_TPose: clav_r%s clav_l%s => fwd %s (chain: +Z=up)" % [_v(cr), _v(cl), _v(fwd_u)])
	var hr: Vector3 = (g_t["hand_r"] as Transform3D).origin
	var hl: Vector3 = (g_t["hand_l"] as Transform3D).origin
	print("SRC руки T: hand_r%s hand_l%s (x<0 = правая сторона, если right=-X)" % [_v(hr), _v(hl)])

	var m_root = load(PLAYER_SCENE).instantiate()
	var m_skel = find_skeleton(m_root)
	var ri := m_skel.find_bone("mixamorig_RightShoulder")
	var li := m_skel.find_bone("mixamorig_LeftShoulder")
	if ri >= 0 and li >= 0:
		var pr: Vector3 = m_skel.get_bone_global_rest(ri).origin
		var pl: Vector3 = m_skel.get_bone_global_rest(li).origin
		var fwd_m := Vector3(0, 1, 0).cross(pr - pl).normalized()
		print("SKIN rest: RightShoulder%s LeftShoulder%s => fwd %s (up=+Y)" % [_v(pr), _v(pl), _v(fwd_m)])
	m_root.free()
	quit(0)

func _fk_clip(lib: AnimationLibrary, clip: String, t: float) -> Dictionary:
	anim = lib.get_animation("Armature|" + clip) if lib.has_animation("Armature|" + clip) else null
	if anim == null:
		print("AX FAIL: нет клипа ", clip)
		quit(1)
		return {}
	_index_tracks()
	var g := {}
	for i in skel.get_bone_count():
		g[skel.get_bone_name(i)] = _mannequin_global(i, t)
	return g

func _delta_deg(a: Transform3D, b: Transform3D) -> String:
	var q := (a.basis.get_rotation_quaternion().inverse() * b.basis.get_rotation_quaternion()).normalized()
	return _axis_deg(q)

func _axis_deg(q: Quaternion) -> String:
	var ang := rad_to_deg(q.get_angle())
	var ax := q.get_axis()
	if ang > 180.0:
		ang = 360.0 - ang
		ax = -ax
	if absf(ang) < 0.5:
		return "≈0"
	return "%5.1f° [%s]" % [ang, _v(ax)]

func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]

func _mix_name(ual_bone: String) -> String:
	var pairs := {
		"pelvis": "mixamorig_Hips", "spine_01": "mixamorig_Spine",
		"spine_03": "mixamorig_Spine2", "neck_01": "mixamorig_Neck",
		"Head": "mixamorig_Head",
		"clavicle_r": "mixamorig_RightShoulder", "upperarm_r": "mixamorig_RightArm",
		"lowerarm_r": "mixamorig_RightForeArm", "hand_r": "mixamorig_RightHand",
		"clavicle_l": "mixamorig_LeftShoulder", "upperarm_l": "mixamorig_LeftArm",
		"lowerarm_l": "mixamorig_LeftForeArm", "hand_l": "mixamorig_LeftHand",
	}
	return pairs.get(ual_bone, "")

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
