extends SceneTree
## ПЛОТНАЯ сверка ретаргета v3 (нейтраль A_TPose): скин vs UAL-источник
## ПО КАЖДОМУ кадру. Метрики на руку (сопоставимы в любых пространствах):
##   высота h = hand.y − foot.y   (над стопами)
##   вынос  f = hand.z − pelvis.z (вперёд от поясницы)
## Скин: player.tscn + подмешанная ual_casts_test.res. Источник: FK манекена.
## Запуск: --headless -s res://Generators/probe_ual_retarget.gd

const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"
const PLAYER_SCENE := "res://Scenes/player.tscn"
const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"
const UAL2 := "res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unity/UAL2_Standard.fbx"

const CLIPS := {
	"Cast_Enter": [UAL1, "Spell_Simple_Enter"],
	"Cast_Loop": [UAL1, "Spell_Simple_Idle_Loop"],
	"Cast_Shoot": [UAL1, "Spell_Simple_Shoot"],
	"Cast_Exit": [UAL1, "Spell_Simple_Exit"],
	"Throw": [UAL2, "OverhandThrow"],
	"Pistol_Shoot": [UAL1, "Pistol_Shoot"],
}
## Гейт (±20% от гейта SOMA-зонда 0.25 м): высота ≤0.30, вынос ≤0.30
const TOL_H := 0.30
const TOL_F := 0.30

var skel: Skeleton3D
var anim: Animation
var tracks: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ── Скин ─────────────────────────────────────────────────────────────
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		print("CMP FAIL: нет player.tscn")
		quit(1)
		return
	var player := packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	var sks := player.find_children("*", "Skeleton3D", true, false)
	if aps.is_empty() or sks.is_empty():
		print("CMP FAIL: нет AnimationPlayer/Skeleton3D")
		quit(1)
		return
	var ap: AnimationPlayer = aps[0]
	var skin: Skeleton3D = sks[0]
	var extra = load(TEST_LIB)
	if extra == null or not (extra is AnimationLibrary):
		print("CMP FAIL: нет " + TEST_LIB)
		quit(1)
		return
	var def := ap.get_animation_library("")
	for an in extra.get_animation_list():
		if def.has_animation(an):
			def.remove_animation(an)
		def.add_animation(an, extra.get_animation(an))

	var idx_r := _find_bone(skin, ["mixamorig_RightHand", "mixamorig1_RightHand"])
	var idx_l := _find_bone(skin, ["mixamorig_LeftHand", "mixamorig1_LeftHand"])
	var idx_rf := _find_bone(skin, ["mixamorig_RightFoot", "mixamorig1_RightFoot"])
	var idx_lf := _find_bone(skin, ["mixamorig_LeftFoot", "mixamorig1_LeftFoot"])
	var idx_hp := _find_bone(skin, ["mixamorig_Hips", "mixamorig1_Hips"])
	if idx_r < 0 or idx_l < 0 or idx_hp < 0:
		print("CMP FAIL: кости скина не найдены")
		quit(1)
		return

	# ── Источники (FK манекена) ─────────────────────────────────────────
	var src_data := {}  # клип → {frames: [{rh, lh, pel, foot}]}
	for clip in CLIPS:
		var path: String = CLIPS[clip][0]
		var root = load_fbx_scene(path)
		if root == null:
			print("CMP FAIL: нет сцены ", path)
			quit(1)
			return
		skel = find_skeleton(root)
		var sap = find_animation_player(root)
		anim = _find_anim(sap.get_animation_library(""), "Armature|" + CLIPS[clip][1])
		_index_tracks()
		var n := int(round(anim.length * 30.0))
		var fr: Array = []
		for f in n + 1:
			var t := minf(float(f) / 30.0, anim.length)
			fr.append({
				"rh": _mannequin_global(skel.find_bone("hand_r"), t).origin,
				"lh": _mannequin_global(skel.find_bone("hand_l"), t).origin,
				"pel": _mannequin_global(skel.find_bone("pelvis"), t).origin,
				"foot": _mannequin_global(skel.find_bone("foot_r"), t).origin,
			})
		src_data[clip] = {"frames": fr, "len": anim.length}
		root.free()

	# ── Сверка по кадрам ────────────────────────────────────────────────
	var all_pass := true
	for clip in CLIPS:
		var s: Dictionary = src_data[clip]
		var n: int = s["frames"].size()
		var mh_r := 0.0
		var mf_r := 0.0
		var mh_l := 0.0
		var mf_l := 0.0
		var worst := ""
		print("=== %s (%d кадров, %.2f с) ===" % [clip, n, s["len"]])
		for f in n:
			var t := minf(float(f) / 30.0, ap.get_animation(clip).length)
			ap.play(clip)
			ap.seek(t, true)
			await process_frame
			var g := skin.global_transform
			var rh: Vector3 = g * skin.get_bone_global_pose(idx_r).origin
			var lh: Vector3 = g * skin.get_bone_global_pose(idx_l).origin
			var pel: Vector3 = g * skin.get_bone_global_pose(idx_hp).origin
			var foot: Vector3 = g * skin.get_bone_global_pose(idx_rf).origin
			var src: Dictionary = s["frames"][f]
			# скин: высота над стопами, вынос от поясницы
			var sh_r := rh.y - foot.y
			var sf_r := rh.z - pel.z
			var sh_l := lh.y - foot.y
			var sf_l := lh.z - pel.z
			# источник: та же метрика в своём пространстве
			var oh_r: float = src["rh"].y - src["foot"].y
			var of_r: float = src["rh"].z - src["pel"].z
			var oh_l: float = src["lh"].y - src["foot"].y
			var of_l: float = src["lh"].z - src["pel"].z
			var dh_r := absf(sh_r - oh_r)
			var df_r := absf(sf_r - of_r)
			var dh_l := absf(sh_l - oh_l)
			var df_l := absf(sf_l - of_l)
			mh_r = maxf(mh_r, dh_r)
			mf_r = maxf(mf_r, df_r)
			mh_l = maxf(mh_l, dh_l)
			mf_l = maxf(mf_l, df_l)
			if maxf(maxf(dh_r, df_r), maxf(dh_l, df_l)) > maxf(TOL_H, TOL_F):
				worst = "f%02d" % f
			if f % 3 == 0 or f == n - 1:
				print("  f%02d R h%.2f/%.2f f%.2f/%.2f | L h%.2f/%.2f f%.2f/%.2f" % [
					f, sh_r, oh_r, sf_r, of_r, sh_l, oh_l, sf_l, of_l])
		var pass_clip := mh_r <= TOL_H and mf_r <= TOL_F and mh_l <= TOL_H and mf_l <= TOL_F
		all_pass = all_pass and pass_clip
		print("  SUM %s: R dh%.2f df%.2f | L dh%.2f df%.2f | %s%s" % [
			clip, mh_r, mf_r, mh_l, mf_l, "PASS" if pass_clip else "FAIL",
			" (худший " + worst + ")" if worst != "" else ""])
	print("CMP %s" % ("ALL PASS" if all_pass else "HAS FAIL"))
	quit(0)

func _find_bone(s: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := s.find_bone(String(n))
		if i >= 0:
			return i
	return -1

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)

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
