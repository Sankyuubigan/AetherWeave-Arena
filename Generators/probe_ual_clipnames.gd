extends SceneTree
## Инвентарь имён клипов UAL1/UAL2: ищем праворукие касты и всё кастоподобное.
## Запуск: --headless -s res://Generators/probe_ual_clipnames.gd

const UAL := [
	"res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unity/UAL1_Standard.fbx",
	"res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unity/UAL2_Standard.fbx",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in UAL:
		var fbx_doc = FBXDocument.new()
		var state = FBXState.new()
		state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
		var err = fbx_doc.append_from_file(path, state)
		if err != OK:
			print("FBX ERR ", path, " ", err)
			continue
		var scene = fbx_doc.generate_scene(state)
		var ap = find_animation_player(scene)
		if ap == null:
			print("нет AP в ", path)
			continue
		var names := ap.get_animation_library("").get_animation_list()
		var copy := []
		for n in names:
			copy.append(String(n).replace("Armature|", ""))
		copy.sort()
		print("=== ", path.get_file(), " (", copy.size(), ") ===")
		print("\n".join(copy))
		scene.free()
	quit(0)

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r = find_animation_player(c)
		if r:
			return r
	return null
