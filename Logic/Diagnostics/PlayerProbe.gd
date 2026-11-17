extends Node
# Диагностический зонд телепорт-бага (Шаг 1 плана «Апгрейд второй карты»).
# Пристёгивается к игроку из ProceduralArena._add_entities. Отвечает на вопросы:
# (1) пересоздаётся ли игрок; (2) есть ли скачки позиции тела; (3) меняется ли сцена;
# (4) умирает ли игрок в первые секунды после прыжка.

var _target: CharacterBody3D
var _last_pos: Vector3
var _frames := 0
var _scene_name := ""

func _ready() -> void:
	_target = get_parent() as CharacterBody3D
	if _target == null:
		push_warning("PlayerProbe: родитель не CharacterBody3D — зонд бесполезен")
		set_physics_process(false)
		return
	_last_pos = _target.global_position
	_scene_name = get_tree().current_scene.name
	print("[Probe] Спавн игрока: ", _target.global_position, " | сцена=", _scene_name)
	# Пересоздание игрока: любой новый CharacterBody3D в дереве — под подозрением.
	get_tree().node_added.connect(_on_node_added)
	# Смерть игрока: если есть HealthComponent — следим за died.
	var hp: Node = _target.find_child("HealthComponent*", true, false)
	if hp and hp.has_signal("died"):
		hp.died.connect(_on_player_died)
		print("[Probe] Слежу за died у ", hp.get_path())

func _on_player_died() -> void:
	print("[Probe] !!! Игрок УМЕР (HealthComponent.died), позиция=", _target.global_position)

func _on_node_added(node: Node) -> void:
	if node is CharacterBody3D:
		print("[Probe] Новый CharacterBody3D в дереве: ", node.name, " поз=", node.position)

func _exit_tree() -> void:
	# Смена сцены или удаление игрока — сам факт диагностичен.
	print("[Probe] Игрок покинул дерево, последняя позиция=", _last_pos)
	var tree := get_tree()
	if tree and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)

func _physics_process(_delta: float) -> void:
	_frames += 1
	var pos: Vector3 = _target.global_position
	if pos.distance_to(_last_pos) > 5.0:
		print("[Probe] !!! СКАЧОК ПОЗИЦИИ: ", _last_pos, " -> ", pos)
		var stack := get_stack()
		if stack.is_empty():
			print("[Probe] Стек пуст (релизная сборка?) — факт скачка зафиксирован")
		else:
			for frame: Dictionary in stack:
				print("[Probe]   из ", frame.get("function"), " : строка ", frame.get("line"))
	if _frames % 120 == 0: # heartbeat раз в 2 секунды — видим Y-координату для kill-z
		print("[Probe] heartbeat: поз=", pos, " vel=", _target.velocity,
			" on_floor=", _target.is_on_floor(), " сцена=", get_tree().current_scene.name)
	_last_pos = pos
	var current := get_tree().current_scene
	if current and current.name != _scene_name:
		print("[Probe] !!! СМЕНА СЦЕНЫ: ", _scene_name, " -> ", current.name)
		_scene_name = current.name
