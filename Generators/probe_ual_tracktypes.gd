extends SceneTree
## ГИПОТЕЗА зеркала: UAL-клипы анимируют кисти POSITION-треками (FK их
## учитывает, ретаргет копирует только ротации). Печатаем типы треков и дельты
## позиций рук относительно rest для Spell_Simple_Idle_Loop / Enter / Shoot.
## Запуск: --headless -s res://Generators/probe_ual_tracktypes.gd

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root = load_fbx_scene(UAL1)
	var skel = find_skeleton(root)
	var ap = find_animation_player(root)
	var lib = ap.get_animation_library("")

	for clip in ["Spell_Simple_Enter", "Spell_Simple_Idle_Loop", "Spell_Simple_Shoot", "Pistol_Shoot"]:
		var a = lib.get_animation("Armature|" + clip) if lib.has_animation("Armature|" + clip) else null
		if a == null:
			print("нет клипа ", clip)
			continue
		print("=== %s (%.2f с) ===" % [clip, a.length])
		var pos_bones := []
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D:
				var p := str(a.track_get_path(i))
				var bone := p.get_slice(":", p.get_slice_count(":") - 1)
				# дельта позиции от rest кости (макс по ключам)
				var bi: int = skel.find_bone(bone)
				var rest: Vector3 = skel.get_bone_rest(bi).origin if bi >= 0 else Vector3.ZERO
				var mx := 0.0
				for k in a.track_get_key_count(i):
					var v: Vector3 = a.track_get_key_value(i, k)
					mx = maxf(mx, (v - rest).length())
				pos_bones.append("%s(Δ%.2f)" % [bone, mx])
		if pos_bones.is_empty():
			print("  позиционных треков НЕТ")
		else:
			print("  POSITION-треки: ", ", ".join(pos_bones))
	quit(0)

func load_fbx_scene(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("FBXDocument error: %s" % error_string(err))
		return null
	return fbx_doc.generate_scene(state)

static func find_skeleton(node: Node) -> Node:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = find_skeleton(c)
		if r:
			return r
	return null

static func find_animation_player(node: Node) -> Node:
	if not node:
		return null
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r = find_animation_player(c)
		if r:
			return r
	return null
