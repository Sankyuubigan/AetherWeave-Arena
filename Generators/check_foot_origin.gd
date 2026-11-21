extends SceneTree

## ГЕЙТ КОНТРАКТА ПОДОШВЫ (Q47-F, гоу юзера 21.11.26): низ merged AABB каждого
## пропа-префаба должен быть y=0 ±1 см — контракт «origin = точка опоры»,
## enforced в build_env_prop.gd (единственная точка сборки). Префаб с низом
## ниже origin «проваливается в пол», выше — «висит в воздухе» (баги-репорты
## Q47 21.11.26, Q22-HANG 20.11.26). Запуск: godot --headless -s .../check_foot_origin.gd

## Собственные билдеры с индивидуальной геометрией — вне контракта этого гейта
## (у них свои гейты): гриб собирает build_mushroom_prop.gd (Stem+CapStatic+
## CapVisual+BounceArea), soft_ground — Q32-конвейер.
const EXCLUDE_DIRS := ["mushroom_bounce", "soft_ground"]
const TOL := 0.01

func _init() -> void:
	var props_root := "res://Graphics/Environment/Props/"
	var da := DirAccess.open(props_root)
	if not da:
		print("SCRIPT ERROR: не открыть ", props_root)
		quit(1)
		return
	var checked := 0
	var failures: Array = []
	for d in da.get_directories():
		if d in EXCLUDE_DIRS:
			print("[SKIP] ", d, " — собственный билдер, вне контракта")
			continue
		var sub := DirAccess.open(props_root.path_join(d))
		if not sub:
			continue
		for f in sub.get_files():
			if not f.ends_with(".tscn"):
				continue
			checked += 1
			var ps: PackedScene = load(props_root.path_join(d).path_join(f))
			if ps == null:
				failures.append(d + "/" + f + " (не загрузить)")
				continue
			var node: Node = ps.instantiate()
			var low := _merged_lowest_y(node as Node3D)
			node.free()
			var ok := absf(low) <= TOL
			print("%s %s/%s: низ %.3f" % ["PASS" if ok else "FAIL", d, f, low])
			if not ok:
				failures.append("%s/%s (низ %.3f)" % [d, f, low])
	print("=== check_foot_origin: ", checked, " префабов, FAIL: ", failures.size(), " ===")
	if failures.size() > 0:
		print("ОШИБКИ: ", failures)
		quit(1)
	else:
		quit(0)

## Сырой низ merged AABB (детached-иерархия: трансформы НАКОПЛЕНИЕМ, global_transform
## не работает; узловой get_aabb() на detached-иерархии ПУСТ — только РЕСУРСНЫЕ
## mesh.get_aabb()/multimesh.get_aabb(); паттерн _geometry_lowest_y из
## build_main_arena.gd).
func _merged_lowest_y(n: Node3D) -> float:
	var lo := 1e9
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var nd: Node = e[0]
		var xf: Transform3D = e[1]
		var next_xf := xf
		if nd is Node3D:
			next_xf = xf * (nd as Node3D).transform
		var ab: AABB
		if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
			ab = (nd as MeshInstance3D).mesh.get_aabb()
		elif nd is MultiMeshInstance3D and (nd as MultiMeshInstance3D).multimesh != null:
			ab = (nd as MultiMeshInstance3D).multimesh.get_aabb()
		else:
			ab = AABB()
		if ab.size != Vector3.ZERO or ab.position != Vector3.ZERO:
			for i in 8:
				var cy := ab.position.y if i < 4 else ab.position.y + ab.size.y
				var cx := ab.position.x if i % 2 == 0 else ab.position.x + ab.size.x
				var cz := ab.position.z if (i % 4) < 2 else ab.position.z + ab.size.z
				lo = minf(lo, (next_xf * Vector3(cx, cy, cz)).y)
		for c in nd.get_children():
			stack.append([c, next_xf])
	if lo >= 1e9:
		return 0.0
	return lo
