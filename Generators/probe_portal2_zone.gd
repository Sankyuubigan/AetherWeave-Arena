extends SceneTree
## Дебаг Q44 №2: позиции порталов после первого физ-тика (подозрение на откат).

func _init() -> void:
	await process_frame
	var ps = load("res://Logic/PortalNode2.gd")
	var pair := Node3D.new()
	root.add_child(pair)
	var a = Area3D.new(); a.set_script(ps); pair.add_child(a)
	a.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 0))
	var b = Area3D.new(); b.set_script(ps); pair.add_child(b)
	b.global_transform = Transform3D(Basis(), Vector3(10, 1.5, 0))
	a.call("build", Color(0.3, 0.9, 0.8), 0.0)
	b.call("build", Color(0.85, 0.4, 1.0), 3.1)
	a.partner = b
	b.partner = a
	print("BEFORE-TICK  a=%s b=%s" % [a.global_position, b.global_position])
	await physics_frame
	print("AFTER-TICK   a=%s b=%s" % [a.global_position, b.global_position])
	await physics_frame
	print("AFTER-TICK2  a=%s b=%s" % [a.global_position, b.global_position])
	quit(0)
