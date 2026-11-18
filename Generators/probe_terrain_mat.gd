extends SceneTree
## Зонд материала рельефа ProceduralArena (19.11.26): легла ли текстура
## forrest_ground_01 на чанки TerrainBuilder (на рендер-снимке холмы
## выглядят плоско-зелёными = подозрение на пустой albedo_texture).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena: Node = (load("res://Scenes/ProceduralArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	for i in 10:
		await process_frame
	var terrain := arena.find_children("Terrain", "StaticBody3D", true, false)
	print("TP terrain_nodes=", terrain.size())
	if terrain.is_empty():
		quit(1)
		return
	var mis := terrain[0].find_children("Chunk_*", "MeshInstance3D", true, false)
	print("TP chunks=", mis.size())
	if mis.is_empty():
		quit(1)
		return
	var mo := (mis[0] as MeshInstance3D).material_override
	print("TP mat_class=", mo.get_class() if mo else "NULL")
	if mo is StandardMaterial3D:
		var m := mo as StandardMaterial3D
		var at := m.albedo_texture
		print("TP albedo_tex=", at.get_class() if at else "NULL", " path=", at.resource_path if at else "NONE")
		print("TP vertex_color=", m.vertex_color_use_as_albedo, " normal=", m.normal_enabled)
	quit(0)
