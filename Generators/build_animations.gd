extends SceneTree

const RAW_DIR = "res://Graphics/Animations/raw/"
const OUTPUT_PATH = "res://Graphics/Animations/shared_animations.res"

var sources = {
	"Idle": RAW_DIR + "Idle.fbx",
	"Run": RAW_DIR + "Running.fbx",
	"Jump": RAW_DIR + "Jumping.fbx",
	"Falling": RAW_DIR + "Falling Idle.fbx",
	"Landing": RAW_DIR + "Falling To Landing.fbx",
	"FrontFlip": RAW_DIR + "Front Flip.fbx"
}

## Циклические клипы (зацикленность не должна зависеть от настроек импорта).
const LOOPED_ANIMS = ["Idle", "Run", "Falling"]

func _init():
	print("Building shared animation library...")
	var lib = AnimationLibrary.new()
	for anim_name in sources:
		var path = sources[anim_name]
		var root = load_fbx_scene(path)
		if not root:
			print("  WARN: cannot load " + path)
			continue
		var fbx_ap = find_animation_player(root)
		if not fbx_ap:
			root.queue_free()
			continue
		var fbx_lib = fbx_ap.get_animation_library("")
		if not fbx_lib:
			root.queue_free()
			continue
		var names = fbx_lib.get_animation_list()
		if names.is_empty():
			root.queue_free()
			continue
		var anim = fbx_lib.get_animation(names[0])
		if anim:
			var dup = anim.duplicate(true)
			for i in dup.get_track_count():
				var path_str = str(dup.track_get_path(i))
				if "mixamorig1_" in path_str:
					path_str = path_str.replace("mixamorig1_", "mixamorig_")
					dup.track_set_path(i, NodePath(path_str))
			dup.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPED_ANIMS else Animation.LOOP_NONE
			lib.add_animation(anim_name, dup)
			var raw = dup.get_track_count()
			print("  ANIM: %s (%d tracks)" % [anim_name, raw])
		root.queue_free()
	ResourceSaver.save(lib, OUTPUT_PATH)
	print("Saved: " + OUTPUT_PATH)
	quit()


func load_fbx_scene(path: String) -> Node:
	var fbx_doc = FBXDocument.new()
	if not fbx_doc:
		print("FBXDocument not available")
		return null
	var state = FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	var err = fbx_doc.append_from_file(path, state)
	if err != OK:
		print("FBXDocument error: %s" % error_string(err))
		return null
	var scene_root = fbx_doc.generate_scene(state)
	return scene_root


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
