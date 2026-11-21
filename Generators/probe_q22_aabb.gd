extends SceneTree

## Q22-FIX гейт: фактические AABB визуала префабов A/B/C (в локале префаба).
## Слоты A/B стоят y=0, но юзер видит «висят в воздухе» — меряем, где низ
## геометрии относительно origin. Формула посадки: slot_y = -aabb_min_y.
## Запуск: powershell -File _tmp_probe/run_godot.ps1 res://Generators/probe_q22_aabb.gd

const PREFABS := {
	"A": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v2_foliage.tscn",
	"B": "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_v3_stock.tscn",
	"C": "res://Graphics/Environment/Props/spruce_mtree/spruce_mtree.tscn",
}

func _init() -> void:
	var wd := create_timer(40.0)
	wd.timeout.connect(func() -> void:
		printerr("[Q22AABB] TIMEOUT")
		quit(1))
	_run()

func _run() -> void:
	for key in PREFABS:
		var ps: PackedScene = load(PREFABS[key])
		if ps == null:
			printerr("[Q22AABB] %s: load FAIL %s" % [key, PREFABS[key]])
			continue
		var node: Node3D = ps.instantiate()
		var bb := _merged_aabb(node)
		# низ/верх геометрии в координатах префаба (слот y=0 => y_world = y_local)
		print("[Q22AABB] %s: min_y=%.3f max_y=%.3f height=%.1f size=(%.1f, %.1f)" % [
			key, bb.position.y, bb.position.y + bb.size.y, bb.size.y, bb.size.x, bb.size.z])
		node.free()
	quit(0)

## Суммарный AABB всех MeshInstance3D, приведённый к корню префаба.
func _merged_aabb(node: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mi3d := mi as MeshInstance3D
		var mesh := mi3d.mesh
		if mesh == null:
			continue
		# AABB меша через все трансформы до корня префаба
		var xf := mi3d.transform
		var parent := mi3d.get_parent()
		while parent != null and parent != node:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		var box := xf * mesh.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	return total
