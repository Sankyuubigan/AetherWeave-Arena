extends SceneTree

## Диагностика для отчёта спецу (22.11.26, купол «криво»): на какой высоте
## отдыхает origin игрока относительно пола MainArena.
## Гипотеза Г-A: origin на ~1.0 м выше пола (тогда весь купол/кольцо, чьи
## высоты считаются от player.y как от пола, уезжают вверх на 1.0 м).
## Гипотеза Г-B: origin = пол (кольцо геометрически на полу, «криво» — чисто
## перспектива плечевой камеры).
## Только замер и печать, код игры не трогает. EXIT 0 = замер прошёл.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== PROBE: rest-Y игрока в MainArena ===")
	var scene = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(scene)
	# 2.0 с СТЕНОЧНОГО времени — физика обязана уложить игрока на пол
	# (headless-кадры суб-мс, кадровый гард ненадёжен).
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 2000000:
		await process_frame
	var player := _find_body(scene)
	if player == null:
		print("RESTY FAIL: CharacterBody3D не найден")
		quit(1)
		return
	print("RESTY player.global_position = ", player.global_position)
	var col := _find_col(player)
	if col != null and col.shape != null and col.shape is CapsuleShape3D:
		var cap: CapsuleShape3D = col.shape
		var bottom: float = player.global_position.y + col.position.y - cap.height / 2.0
		print("RESTY капсула: pos=", col.position, " h=", cap.height,
				" r=", cap.radius, " → низ капсулы в мире Y = ", bottom)
	var gw := player.get_node_or_null("GraphicsWrapper")
	if gw != null:
		print("RESTY GraphicsWrapper.global_position = ", gw.global_position)
	var skel := _find_skel(player)
	if skel != null:
		var bi := skel.find_bone("mixamorig_Hips")
		if bi >= 0:
			var gp: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
			print("RESTY Hips мир Y = ", gp.origin.y, " | player.origin Y = ",
					player.global_position.y)
		else:
			print("RESTY кость Hips не найдена")
	var fb := _find_by_name(scene, "FloorBacking")
	if fb != null and fb is Node3D:
		print("RESTY FloorBacking.global_position = ", (fb as Node3D).global_position)
	else:
		print("RESTY FloorBacking не найден (нефатально)")
	print("RESTY DONE")
	quit(0)

func _find_body(n: Node) -> Node:
	if n is CharacterBody3D:
		return n
	for c in n.get_children():
		var r := _find_body(c)
		if r != null:
			return r
	return null

func _find_col(n: Node) -> Node:
	if n is CollisionShape3D:
		return n
	for c in n.get_children():
		var r := _find_col(c)
		if r != null:
			return r
	return null

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _find_by_name(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var r := _find_by_name(c, nm)
		if r != null:
			return r
	return null
