extends SceneTree
## Минимальный репро: какой source_code у загруженного Skill.gd и вызывается ли execute.

func _init() -> void:
	var s = load("res://Logic/Skills/Skill.gd")
	var src: String = s.source_code
	print("MIN: path=", s.resource_path, " len=", src.length(), " has_temp=", src.contains("TEMP-DEBUG"))
	print("MIN: tail=", src.substr(max(0, src.length() - 100)).replace("\n", " | "))
	var inst = s.new()
	inst.shake = 1.0
	print("MIN: shake_readback=", inst.shake)
	inst.execute(null, {})
	print("MIN: execute_returned")
	quit()
