extends SceneTree
## Зонд 1 (AnimationTree): авторитетный дамп API нашей сборки 4.8-beta3 —
## свойства/методы классов дерева. Headless, без сцены.
## Запуск: Godot --headless -s res://Generators/probe_tree_api.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for cls in ["AnimationTree", "AnimationNodeStateMachine",
			"AnimationNodeStateMachineTransition", "AnimationNodeAnimation",
			"AnimationNodeTimeScale", "AnimationNodeBlendTree"]:
		var props = ClassDB.class_get_property_list(cls, true)
		var names: Array[String] = []
		for p in props:
			names.append(str(p["name"]) + ":" + str(p["type"]))
		print("PROPS ", cls, " → ", ", ".join(names))
		var methods = ClassDB.class_get_method_list(cls, true)
		var mnames: Array[String] = []
		for m in methods:
			mnames.append(str(m["name"]))
		print("METHODS ", cls, " → ", ", ".join(mnames))
	# Константы переходов (имена через ClassDB — не по памяти)
	for cls in ["AnimationNodeStateMachineTransition", "AnimationTree",
			"AnimationNodeStateMachine", "AnimationNodeStateMachinePlayback"]:
		var consts = ClassDB.class_get_integer_constant_list(cls, true)
		var cnames: Array[String] = []
		for c in consts:
			cnames.append(String(c) + "=" + str(ClassDB.class_get_integer_constant(cls, c)))
		print("CONSTS ", cls, " → ", ", ".join(cnames))
	quit(0)
