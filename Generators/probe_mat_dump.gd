extends SceneTree
## Дамп материалов surface'ов мешей A (v2) vs B (v3) — поиск различий.

func _init() -> void:
	await process_frame
	for tag in ["v2_foliage", "v3_stock"]:
		for mi_name in ["_mesh_0.res", "_mesh_1.res"]:
			var path := "res://Graphics/Environment/Props/pine_tree_01/pine_tree_01_%s%s" % [tag, mi_name]
			var mesh: ArrayMesh = load(path)
			print("=== %s %s (surfaces=%d)" % [tag, mi_name, mesh.get_surface_count()])
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as BaseMaterial3D
				if mat == null:
					print("  s%d: NO MATERIAL" % s)
					continue
				var tex := mat.albedo_texture
				print("  s%d: name=%s tex=%s albedo=%s scissor=%.2f cull=%d transp=%d orm_tex=%s" % [
					s, mat.resource_name,
					tex.resource_path.get_file() if tex else "none",
					str(mat.albedo_color),
					mat.alpha_scissor_threshold,
					mat.cull_mode,
					mat.transparency,
					(mat.metallic_texture.resource_path.get_file() if mat.metallic_texture else "none")])
	quit(0)
