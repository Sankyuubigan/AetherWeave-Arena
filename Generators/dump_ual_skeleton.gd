extends SceneTree
## Кости скелета UAL + пути треков Spell_Simple_Shoot — оценка ретаргета
## Unity Mannequin → mixamorig_ (наш скин Ch24_nonPBR).

const UAL1 := "res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root = load_fbx_scene(UAL1)
	if not root:
		print("load FAIL")
		quit(1)
		return
	var skel = find_skeleton(root)
	if skel:
		print("Skeleton: ", skel.name, " bones=", skel.get_bone_count())
		for i in skel.get_bone_count():
			print("  bone[%d] %s parent=%s" % [i, skel.get_bone_name(i), skel.get_bone_name(skel.get_bone_parent(i)) if skel.get_bone_parent(i) >= 0 else "-"])
	var ap = find_animation_player(root)
	if ap:
		var lib = ap.get_animation_library("")
		for target in ["Spell_Simple_Shoot", "Spell_Simple_Idle_Loop", "OverhandThrow"]:
			var full: String = "Armature|" + str(target)
			if not lib.has_animation(full):
				print("нет ", full)
				continue
			var anim: Animation = lib.get_animation(full)
			print("=== %s: %.2f с, треков %d ===" % [target, anim.length, anim.get_track_count()])
			var shown := 0
			for i in anim.get_track_count():
				var p := str(anim.track_get_path(i))
				if ":mixamorig" in p or "Hips" in p or shown < 6:
					print("  ", p, " [", anim.track_get_type(i), "]")
					shown += 1
				if shown > 12:
					break
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
