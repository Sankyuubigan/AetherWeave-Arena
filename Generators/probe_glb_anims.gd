extends SceneTree
## Проверка GLB-источников: сколько анимаций вшито (для 3D-вьюера).

const GLBS := [
	"res://Graphics/Animations/raw/Universal Animation Library[Standard]/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb",
	"res://Graphics/Animations/raw/Universal Animation Library 2[Standard]/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in GLBS:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(path, state)
		if err != OK:
			print("GLB ERR ", err, " ", path.get_file())
			continue
		var anims := state.get_animations()
		var names := []
		for a in anims:
			names.append(String(a.resource_name))
		names.sort()
		print("GLB %s anims=%d first=%s" % [path.get_file(), anims.size(), ", ".join(names.slice(0, 5))])
	quit(0)
