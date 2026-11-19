extends SceneTree

## Q31 шаг 1 (гейт): SoftBody3D в 4.8-beta3 — промин RigidBody3D-шаром,
## возврат формы, отсутствие «взрыва» симуляции. Headless (физика тикает).

const CAP := "res://Graphics/Environment/Props/mushroom_bounce/mushroom_cap.tres"
const PIN_PATH := "Anchor"  # внутри пробного корня

func _init() -> void:
	await physics_frame
	var base := Node3D.new()
	root.add_child(base)
	var anchor := Node3D.new()
	anchor.name = "Anchor"
	anchor.position = Vector3(0, 1.0, 0)
	base.add_child(anchor)

	var cap_mesh: ArrayMesh = load(CAP)
	var n: int = (cap_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("[SOFT] mesh verts: ", n)
	var soft := SoftBody3D.new()
	soft.position = Vector3(0, 1.0, 0)
	soft.mesh = cap_mesh
	soft.total_mass = 5.0
	soft.linear_stiffness = 0.6
	soft.damping_coefficient = 0.05
	soft.simulation_precision = 8
	base.add_child(soft)
	await physics_frame
	await physics_frame

	# Пины кромки (кольцо RINGS): индексы n-24..n-1
	var pinned := 0
	for i in range(n - 24, n):
		soft.set_point_pinned(i, true, NodePath("../Anchor"))
		pinned += 1
	print("[SOFT] pinned skirt points: ", pinned)
	await physics_frame

	# База покоя
	var rest: Array = []
	for i in range(n):
		rest.append(soft.get_point_transform(i))
	var rest_y_top: float = rest[0].y
	print("[SOFT] rest top pole: %.3f" % rest_y_top)

	# Шар падает с 5 м над шляпкой
	var ball := RigidBody3D.new()
	var bs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.5
	bs.shape = sph
	ball.add_child(bs)
	var bm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	bm.mesh = sm
	ball.add_child(bm)
	ball.mass = 4.0
	ball.position = Vector3(0, 7.0, 0)
	base.add_child(ball)

	# Меряем: максимальный промин за 2 с
	var max_dent := 0.0
	for t in range(20):
		await physics_frame
		for i in range(n):
			var off: Vector3 = soft.get_point_transform(i) - rest[i]
			if -off.y > max_dent:
				max_dent = -off.y
	print("[SOFT] max dent (2s, ball on cap): %.3f м" % max_dent)

	# Убираем шар, ждём возврат 2.5 с
	ball.queue_free()
	for t in range(15):
		await physics_frame
	var worst := 0.0
	var exploded := false
	for i in range(n):
		var off: Vector3 = soft.get_point_transform(i) - rest[i]
		if off.length() > 1.5:
			exploded = true
		if off.length() > worst:
			worst = off.length()
	print("[SOFT] after settle: worst offset %.3f м, exploded=%s" % [worst, exploded])

	var ok := true
	if max_dent < 0.05:
		print("[SOFT] FAIL: промина нет (%.3f < 0.05)" % max_dent)
		ok = false
	if worst > 0.35:
		print("[SOFT] FAIL: форма не вернулась (%.3f > 0.35)" % worst)
		ok = false
	if exploded:
		print("[SOFT] FAIL: взрыв симуляции")
		ok = false
	print("[SOFT] GATE: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
