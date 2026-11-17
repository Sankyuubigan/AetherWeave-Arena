extends SceneTree
## Зонд ИСТОЧНИКА UAL (до ретаргета): траектории кистей по кадрам у кандидатов
## «одноручный каст правой рукой». Числовой вердикт о движении: какая рука
## ведёт, высота, выброс вперёд. Полный список клипов — dump_ual_anims.gd.
##
## Запуск: --headless -s res://Generators/probe_ual_source.gd

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const UAL2 := "res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unity/UAL2_Standard.fbx"

const CANDIDATES := {
	UAL1: ["Spell_Simple_Enter", "Spell_Simple_Idle_Loop", "Spell_Simple_Shoot",
		"Spell_Simple_Exit", "Pistol_Shoot", "Punch_Cross", "Sword_Attack", "Push_Loop"],
	UAL2: ["OverhandThrow", "Melee_Hook"],
}

var skel: Skeleton3D
var anim: Animation
var tracks: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in CANDIDATES:
		var root = load_fbx_scene(path)
		if root == null:
			print("PROBE FAIL: нет сцены ", path)
			continue
		var s = find_skeleton(root)
		var ap = find_animation_player(root)
		if s == null or ap == null:
			print("PROBE FAIL: нет скелета/аниматора ", path)
			root.free()
			continue
		skel = s
		var lib = ap.get_animation_library("")
		for clip in CANDIDATES[path]:
			var a = _find_anim(lib, "Armature|" + clip)
			if a == null:
				print("=== %s: НЕТ ===" % clip)
				continue
			anim = a
			_index_tracks()
			var h_r := skel.find_bone("hand_r")
			var h_l := skel.find_bone("hand_l")
			var pel := skel.find_bone("pelvis")
			var n := int(round(anim.length * 30.0))
			var r_zmax := -9999.0
			var r_y_at := 0.0
			var r_zmin := 9999.0
			var l_zmax := -9999.0
			var l_y_at := 0.0
			var y_min := 9999.0
			var y_max := -9999.0
			var pel_y := 0.0
			print("=== %s (%.2f c, ~%d кадров@30) ===" % [clip, anim.length, n])
			for f in n + 1:
				var t := minf(float(f) / 30.0, anim.length)
				var pr: Vector3 = _mannequin_global(h_r, t).origin
				var pl: Vector3 = _mannequin_global(h_l, t).origin
				var pp: Vector3 = _mannequin_global(pel, t).origin
				pel_y = pp.y
				y_min = minf(y_min, minf(pr.y, pl.y))
				y_max = maxf(y_max, maxf(pr.y, pl.y))
				if pr.z > r_zmax:
					r_zmax = pr.z
					r_y_at = pr.y
				r_zmin = minf(r_zmin, pr.z)
				if pl.z > l_zmax:
					l_zmax = pl.z
					l_y_at = pl.y
				if f % 3 == 0:
					print("  PATH f%02d t%.2f R(%.2f,%.2f,%.2f) L(%.2f,%.2f,%.2f)" % [f, t, pr.x, pr.y, pr.z, pl.x, pl.y, pl.z])
			print("  SUM: pelvis_y=%.2f | R z[%.2f..%.2f] y@zmax=%.2f | L zmax=%.2f y@zmax=%.2f | руки y[%.2f..%.2f]" % [
				pel_y, r_zmin, r_zmax, r_y_at, l_zmax, l_y_at, y_min, y_max])
		root.free()
	quit(0)

func _find_anim(fbx_lib: AnimationLibrary, src_anim_name: String) -> Animation:
	var a = fbx_lib.get_animation(src_anim_name) \
			if fbx_lib and fbx_lib.has_animation(src_anim_name) else null
	if a == null:
		for n in fbx_lib.get_animation_list():
			if String(n).ends_with(String(src_anim_name).split("|")[1]):
				a = fbx_lib.get_animation(n)
				break
	return a

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
