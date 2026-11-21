extends SceneTree
## Диагностика: где теряется низ 0.089 у карточного дерева (живой инстанс).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var inst: Node3D = load("res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_a.tscn").instantiate()
	root.add_child(inst)
	await physics_frame
	_dump(inst, 0)
	quit(0)

func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var origin := ""
	if n is Node3D:
		origin = str((n as Node3D).transform.origin)
	print(pad, n.name, " [", n.get_class(), "] origin=", origin)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var ab := mi.mesh.get_aabb()
			var g := mi.global_transform
			print(pad, "  meshAABB pos=", ab.position, " end=", ab.end,
					" global.origin=", g.origin,
					" низ_мира=%.3f" % (g * Vector3(ab.position.x, ab.position.y, ab.position.z)).y)
		if mi.custom_aabb.size.x > 0:
			print(pad, "  custom_aabb=", mi.custom_aabb)
	for c in n.get_children():
		_dump(c, depth + 1)
