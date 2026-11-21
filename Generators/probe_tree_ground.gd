extends SceneTree
## Диагностика «деревья висят в воздухе» (баг-репорт юзера 20.11.26, E/A/B):
## слоты ставят инстанс на y=0 — если origin префаба не в подошве (центр
## ствола/кроны), низ геометрии оказывается выше земли. Меряем низ AABB всех
## MeshInstance3D/MultiMeshInstance3D каждого префаба в слоте.
## Запуск: timeout 60 godot --headless -s res://Generators/probe_tree_ground.gd

const TREES := {
	"A pine_tree_01_v4_cone_a": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_a.tscn",
	"E pine_tree_01_v2_foliage_b": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage_b.tscn",
	"B pine_tree_01_v4_cone_b": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v4_cone_b.tscn",
	"C spruce_mtree": "res://Graphics/Environment/Props/spruce_mtree/spruce_mtree.tscn",
	"D spruce_mtree_D": "res://Graphics/Environment/Props/spruce_mtree_D/spruce_mtree_D.tscn",
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for k: String in TREES:
		var ps: PackedScene = load(TREES[k])
		if ps == null:
			print("[TREE] %s: префаб не грузится" % k)
			continue
		var inst: Node3D = ps.instantiate()
		root.add_child(inst)
		await physics_frame
		var min_y := 1e9
		var max_y := -1e9
		for mi in _find_meshes(inst):
			var aabb: AABB = mi.get_aabb()
			var xf: Transform3D = mi.global_transform * _owner_to_inner(mi, inst)
			# 8 углов AABB в мир
			for cx in [aabb.position.x, aabb.end.x]:
				for cy in [aabb.position.y, aabb.end.y]:
					for cz in [aabb.position.z, aabb.end.z]:
						var w := xf * Vector3(cx, cy, cz)
						min_y = minf(min_y, w.y)
						max_y = maxf(max_y, w.y)
		print("[TREE] %-28s низ=%.3f  верх=%.3f  (висит на %.3f м)" % [k, min_y, max_y, maxf(0.0, min_y)])
		inst.queue_free()
	quit(0)

func _find_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D or n is MultiMeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out

func _owner_to_inner(mi: Node, _inst: Node) -> Transform3D:
	# aabb локальный к mi; global_transform уже учитывает полную цепочку
	return Transform3D()
