extends SceneTree

## Проба QUEUE Q26 (фидбэк юзера: «враги просто исчезают и всё»): рэгдоллы
## врагов ада. Загружаем HellArena, убиваем первого врага, считаем куклы-трупы
## (RagdollCorpse). Кукла должна заспавниться в current_scene и остаться после
## скрытия врага. Гейт: GATE ALL PASS.

var fails := 0

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

func _init() -> void:
	await process_frame
	_run()

func _run() -> void:
	var ps: PackedScene = load("res://Scenes/HellArena.tscn")
	_check("HellArena загружена", ps != null)
	if ps == null:
		print("GATE FAILURES: -")
		quit(1)
		return
	var scene := ps.instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout

	var enemies := []
	_collect_enemies(scene, enemies)
	_check("враги найдены (%d)" % enemies.size(), enemies.size() > 0)
	if enemies.is_empty():
		print("GATE FAILURES: -")
		quit(1)
		return

	var enemy = enemies[0]
	enemy._last_hit_amount = 60
	enemy._last_hit_dir = Vector3(0, 1, 0)
	enemy.die()
	await create_timer(1.5).timeout

	var corpses := _count_corpses(scene)
	_check("кукла-труп заспавнилась (%d)" % corpses, corpses >= 1)
	_check("враг скрыт (mesh_node.hide)", enemy.mesh_node != null and not enemy.mesh_node.visible)
	_check("враг жив как узел (корутина respawn)", is_instance_valid(enemy))

	if fails == 0:
		print("GATE ALL PASS")
		quit(0)
	else:
		print("GATE FAILURES: %d" % fails)
		quit(1)

func _collect_enemies(node: Node, out: Array) -> void:
	if node.has_method("die") and node.has_method("respawn"):
		out.append(node)
	for c in node.get_children():
		_collect_enemies(c, out)

func _count_corpses(node: Node) -> int:
	var n := 0
	var s = node.get_script()
	if s != null and s.resource_path.ends_with("RagdollCorpse.gd"):
		n += 1
	for c in node.get_children():
		n += _count_corpses(c)
	return n
