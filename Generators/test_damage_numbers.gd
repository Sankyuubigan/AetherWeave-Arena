extends SceneTree
## Тест цифр урона (PRP «18.11.26 Демо-фишки Godot»).
## Запуск: engine --headless -s res://Generators/test_damage_numbers.gd
## Гейты: spawn_at создаёт Label3D в current_scene; текст/цвет урона и лечения;
## после LIFETIME цифры удаляются.

const DN = preload("res://Graphics/DamageNumbers.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "TestScene"
	root.add_child(scene)
	current_scene = scene

	var dn := DN.new()
	root.add_child(dn)
	await process_frame

	dn.spawn_at(Vector3(1, 2, 3), 25, false)
	dn.spawn_at(Vector3(4, 5, 6), 10, true)
	await process_frame

	var labels := scene.find_children("*", "Label3D", true, false)
	_check(labels.size() == 2, "две цифры в сцене, получено %d" % labels.size())
	var dmg: Label3D = labels[0] if String(labels[0].text) == "25" else labels[1]
	var heal: Label3D = labels[0] if String(labels[0].text) == "+10" else labels[1]
	_check(String(dmg.text) == "25", "текст урона «25»")
	_check(String(heal.text) == "+10", "текст лечения «+10»")
	_check(dmg.modulate.r > 0.9 and dmg.modulate.g < 0.8, "урон — оранжевый")
	_check(heal.modulate.g > 0.9 and heal.modulate.r < 0.6, "лечение — зелёный")
	_check(dmg.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "billboard включён")
	_check(dmg.no_depth_test, "no_depth_test включён")

	# После LIFETIME (1.1 с) + запас на кадр tween — цифры удалены.
	await create_timer(1.5).timeout
	labels = scene.find_children("*", "Label3D", true, false)
	_check(labels.size() == 0, "цифры удалились после фейда (осталось %d)" % labels.size())

	print("DAMAGE-NUMBERS: ALL PASS")
	quit(0)

func _check(cond: bool, what: String) -> void:
	if not cond:
		print("DAMAGE-NUMBERS: FAIL — ", what)
		quit(1)
