extends SceneTree
## Скан UAL-паков (Mixamo Universal Animation Library): список ВСЕХ анимаций
## внутри каждого FBX. Цель — найти готовые касты (spell cast / throw) и не
## качать их вручную, если они уже в паках.

const FILES := [
	"res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx",
	"res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unity/UAL2_Standard.fbx",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in FILES:
		print("=== ", path.get_file(), " ===")
		var root = load_fbx_scene(path)
		if not root:
			print("  load FAIL")
			continue
		var ap = find_animation_player(root)
		if not ap:
			print("  нет AnimationPlayer")
			root.queue_free()
			continue
		var lib = ap.get_animation_library("")
		if not lib:
			print("  нет библиотеки")
			root.queue_free()
			continue
		var names = lib.get_animation_list()
		print("  анимаций: ", names.size())
		for n in names:
			print("    %s (%.2f с)" % [n, lib.get_animation(n).length])
		root.queue_free()
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
