extends SceneTree

## Тест QUEUE Q7: ChunkedNavMesh — bake_chunk печёт ТОЛЬКО поддерево чанка
## (parse_source_geometry_data с root_node = чанк), rebake_chunk обновляет
## навмеш региона. Гейт: GATE ALL PASS, иначе quit(1).

const CNM = preload("res://Logic/ChunkedNavMesh.gd")

var fails := 0

func _init() -> void:
	await process_frame
	_run()

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

func _add_box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)

func _run() -> void:
	var scene := Node3D.new()
	current_scene = scene
	root.add_child(scene)

	# Чанк A: пол + стена (препятствие для навмеша). Чанк B: только пол,
	# смещён на 20 м — parse_source_geometry_data(…, chunk_root) не должен
	# залезать в чужое поддерево.
	var chunkA := Node3D.new()
	chunkA.name = "ChunkA"
	scene.add_child(chunkA)
	_add_box(chunkA, Vector3(0, -0.25, 0), Vector3(16, 0.5, 16))
	_add_box(chunkA, Vector3(0, 1.0, 0), Vector3(2, 2, 0.5))

	var chunkB := Node3D.new()
	chunkB.name = "ChunkB"
	chunkB.position = Vector3(20, 0, 0)
	scene.add_child(chunkB)
	_add_box(chunkB, Vector3(0, -0.25, 0), Vector3(16, 0.5, 12))

	var regionA := CNM.bake_chunk(chunkA, chunkA)
	_check("регион A в чанке", regionA.get_parent() == chunkA)
	_check("имя региона NavRegion_ChunkA", regionA.name == "NavRegion_ChunkA")
	_check("полигоны A > 0", regionA.navigation_mesh.get_polygon_count() > 0)

	var regionB := CNM.bake_chunk(chunkB, chunkB)
	_check("полигоны B > 0", regionB.navigation_mesh.get_polygon_count() > 0)

	var count := CNM.rebake_chunk(regionB, chunkB)
	_check("ребейк B: полигоны > 0", count > 0)
	_check("ребейк применён к региону", regionB.navigation_mesh.get_polygon_count() == count)

	if fails == 0:
		print("GATE ALL PASS")
	else:
		print("GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
